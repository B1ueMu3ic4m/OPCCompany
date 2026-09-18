// opc — the headless entry point for OPC Company (v0.2.x).
//
// Talks to the SAME CompanyStore the GUI drives, on the SAME local snapshot
// (CompanyPersistence) — run the company without opening the window. This
// executable links ONLY the portable core, so it is the first buildable
// artifact on the Windows path (M0 verified: docs/WINDOWS_COMPILE_REPORT.md —
// logic package compiles on Windows with zero Apple-UI imports).
//
// No external argument-parsing dependency: the command set is tiny and a
// hand-rolled parser keeps the macOS build graph unchanged (adding a SwiftPM
// dependency would touch it — this only adds one executable target).
//
// Commands:
//   opc status              company snapshot (products, team, tasks, approvals)
//   opc goal "TEXT"         hand a boss goal to the CTO
//   opc advance             push every open supervisor goal one step
//   opc report              boss-readable progress report for the current product
//   opc help / --help       usage

import Foundation
import OPCCompanyCore

// The store is @MainActor; the CLI is single-shot, so isolate explicitly
// instead of spinning a UI runloop.
@MainActor
private func withStore(_ body: (CompanyStore) throws -> Void) throws {
    try body(CompanyStore.bootstrap(loadPersisted: true))
}

// Errors surfaced as a clean "error: …" line + exit code, never a Swift trap.
struct CLIError: Error { let message: String }

private func usage() -> String {
    """
    opc — run your local AI company from the terminal. (v0.4.0)

    USAGE:
      opc status                 company snapshot (products, team, tasks, approvals)
      opc goal "TEXT"            send a boss goal to the CTO (creates the chain)
      opc advance                let the CTO advance every open goal one step
      opc report                 boss-readable progress report (current product)
      opc approvals              list pending approvals with their ids
      opc decide <id> approve|reject
                                 resolve one pending approval (same store path
                                 as the GUI; refuses stale/double taps loudly)
      opc products               list all products (ids included)
      opc use <id>               switch the selected product (same store path
                                 as the GUI sidebar; unknown ids refused)

    All commands read and write the same local company snapshot the desktop app
    uses, so CLI and GUI stay in sync. State lives under the OPC app-support
    directory (override with OPC_COMPANY_SUPPORT_DIR); nothing leaves your machine.
    """
}

@MainActor
private func requireProduct(_ store: CompanyStore) throws -> ProductWorkspace {
    guard let product = store.selectedProduct else {
        throw CLIError(message: "no product selected — open the desktop app once and pick/create a product first.")
    }
    return product
}

// Write commands (goal/advance) enforce the core's cross-process exclusivity
// (OPCWriteGuard — shared with the M3 Flutter FFI bridge so the rule can
// never drift between entry points): the desktop app may hold unflushed
// state in this very snapshot; sequential CLI runs are safe (each reloads
// from disk; the CLI's comm name `opc` never self-matches pgrep's target).
// Override: OPC_ALLOW_CONCURRENT_WRITE=1 (headless CI, scripted setups).
private func guardNoConcurrentWriter() throws {
    do {
        try OPCWriteGuard.ensureExclusiveAccess()
    } catch let e as OPCConcurrentWriterError {
        throw CLIError(message: e.message)
    }
}

@main
struct OPC {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        let command = args.first ?? "help"
        let rest = Array(args.dropFirst())

        do {
            switch command {
            case "help", "--help", "-h":
                print(usage())
            case "version", "--version":
                print("opc 0.4.0")
            case "status":
                try status()
            case "goal":
                try goal(rest)
            case "advance":
                try advance()
            case "report":
                try report()
            case "approvals":
                try approvals()
            case "decide":
                try decide(rest)
            case "products":
                try products()
            case "use":
                try use(rest)
            default:
                FileHandle.standardError.write(Data("unknown command: \(command)\n\n".utf8))
                print(usage())
                exit(64) // EX_USAGE
            }
        } catch let e as CLIError {
            FileHandle.standardError.write(Data("error: \(e.message)\n".utf8))
            exit(1)
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
    }

    @MainActor
    static func status() throws {
        try withStore { store in
            let product = store.selectedProduct?.name ?? "— (no product yet)"
            print("OPC Company — \(product)")
            print("  products: \(store.products.count)   employees: \(store.agents.count)")

            let scoped = store.tasks.filter { $0.productID == store.selectedProductID }
            if scoped.isEmpty {
                print("  tasks: none yet — run: opc goal \"your first objective\"")
            } else {
                var counts: [String: Int] = [:]
                for t in scoped { counts[t.status.title, default: 0] += 1 }
                let line = counts.sorted { $0.value > $1.value }
                    .map { "\($0.value) \($0.key)" }.joined(separator: ", ")
                print("  tasks (\(scoped.count)): \(line)")
            }

            let pending = store.approvals.filter { $0.productID == store.selectedProductID && $0.status == .pending }.count
            print("  approvals awaiting boss: \(pending)")
            let running = store.runningAgentIDs.count
            if running > 0 { print("  employees with a running CLI session: \(running)") }
        }
    }

    @MainActor
    static func goal(_ rest: [String]) throws {
        let text = rest.joined(separator: " ")
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw CLIError(message: "usage: opc goal \"one-sentence objective\"")
        }
        try guardNoConcurrentWriter()
        try withStore { store in
            _ = try requireProduct(store)
            let before = Set(store.tasks.map(\.id))
            guard store.startCTOSupervisorGoal(goal: text) != nil else {
                throw CLIError(message: "goal rejected (empty after trimming)")
            }
            let created = store.tasks.filter { !before.contains($0.id) }
            print("Goal handed to the CTO. \(created.count) task(s) created:")
            for t in created { print("  [\(t.status.title)] \(t.title)") }
            print("Next: `opc advance` to move the chain, `opc status` to watch.")
        }
    }

    @MainActor
    static func advance() throws {
        try guardNoConcurrentWriter()
        try withStore { store in
            let progressed = store.advanceCTOSupervisorLoop()
            print(progressed
                  ? "CTO advanced at least one goal — run `opc status` for the new state."
                  : "Nothing to advance: no open supervisor loops, or the next step needs a real employee CLI run (start those from the desktop app, or file more goals).")
        }
    }

    @MainActor
    static func report() throws {
        try withStore { store in
            let product = try requireProduct(store)
            let scoped = store.tasks.filter { $0.productID == store.selectedProductID }
            let done = scoped.filter { $0.status == .done }.count
            let failed = scoped.filter { $0.status == .failed }.count
            let blocked = scoped.filter { $0.status == .blocked }.count
            let open = scoped.count - done - failed

            print("## \(product.name) — progress \(scoped.count == 0 ? "n/a" : "\(done)/\(scoped.count)")")
            print("")
            if scoped.isEmpty {
                print("- No tasks yet. File a goal: `opc goal \"...\"`.")
            } else {
                if open > 0 { print("- \(open) task(s) still moving") }
                if blocked > 0 { print("- \(blocked) blocked — inspect the task graph in the app") }
                if failed > 0 { print("- \(failed) failed — reviewer should re-scope") }
                if done > 0 { print("- \(done) done") }
            }
            let pending = store.approvals.filter { $0.productID == store.selectedProductID && $0.status == .pending }
            if pending.isEmpty {
                print("- nothing needs your decision right now")
            } else {
                print("- \(pending.count) approval(s) need the boss:")
                for a in pending.prefix(5) { print("    · \(a.title)") }
            }

            let recent = store.agentMessages.filter { $0.productID == store.selectedProductID }.suffix(5)
            if !recent.isEmpty {
                print("")
                print("recent collaboration:")
                for m in recent { print("  · \(m.subject)") }
            }
        }
    }

    @MainActor
    static func approvals() throws {
        try withStore { store in
            let pending = store.approvals.filter {
                $0.productID == store.selectedProductID && $0.status == .pending
            }
            if pending.isEmpty {
                print("No pending approvals for \(store.selectedProduct?.name ?? "the selected product").")
                return
            }
            print("Pending approvals (\(pending.count)) — decide with: opc decide <id> approve|reject")
            for a in pending {
                print("  \(a.id.uuidString)")
                print("    \(a.title) — \(a.reason)")
            }
        }
    }

    @MainActor
    static func decide(_ rest: [String]) throws {
        guard rest.count == 2,
              let approvalID = UUID(uuidString: rest[0]),
              let approved = ["approve": true, "reject": false][rest[1]] else {
            throw CLIError(message: "usage: opc decide <approval-id> approve|reject  (ids from: opc approvals)")
        }
        try guardNoConcurrentWriter()
        try withStore { store in
            do {
                // Same checked facade the bridge verb uses: an unknown or
                // already-decided id refuses loudly instead of exiting 0
                // having done nothing.
                try store.decideApprovalChecked(approvalID, approved: approved)
            } catch let e as ApprovalDecisionError {
                throw CLIError(message: e.bridgeReason(idString: approvalID.uuidString))
            }
            store.saveSnapshot()
            print(approved ? "Approved." : "Rejected.")
        }
    }

    @MainActor
    static func products() throws {
        try withStore { store in
            print("Products (\(store.products.count)) — switch with: opc use <id>")
            for p in store.products {
                let marker = p.id == store.selectedProductID ? "*" : " "
                print("  \(marker) \(p.id.uuidString)  \(p.name)  [\(p.stage.title)]")
            }
        }
    }

    @MainActor
    static func use(_ rest: [String]) throws {
        guard rest.count == 1, let productID = UUID(uuidString: rest[0]) else {
            throw CLIError(message: "usage: opc use <product-id>  (ids from: opc products)")
        }
        try guardNoConcurrentWriter()
        try withStore { store in
            // Same rule as the bridge's product_select verb: selectProduct()
            // would be a silent no-op on an unknown id — upgrade to refusal.
            guard store.products.contains(where: { $0.id == productID }) else {
                throw CLIError(message: "no product with id \(rest[0]) — run: opc products")
            }
            store.selectProduct(productID)
            store.saveSnapshot()
            print("Now working on: \(store.selectedProduct?.name ?? rest[0])")
        }
    }
}
