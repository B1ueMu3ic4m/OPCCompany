// opc — the headless entry point for OPC Company (v0.2.0).
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
    opc — run your local AI company from the terminal. (v0.2.0)

    USAGE:
      opc status                 company snapshot (products, team, tasks, approvals)
      opc goal "TEXT"            send a boss goal to the CTO (creates the chain)
      opc advance                let the CTO advance every open goal one step
      opc report                 boss-readable progress report (current product)

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

/// Write commands (goal/advance) refuse to run while the desktop app is
/// alive: both processes share ONE snapshot file with last-writer-wins
/// merge, so a CLI save from stale-read state would silently rewind whatever
/// the app persists meanwhile. Sequential CLI runs (goal && advance) are
/// safe — each reloads from disk, and only a real GUI process (comm name
/// "OPCCompany"; the CLI's own name is "opc", so it never self-matches)
/// can hold unflushed in-memory state. On platforms without pgrep (Windows
/// port) the check no-ops; a proper cross-process lock belongs to M3 when
/// the Flutter shell introduces real concurrency.
/// Override with OPC_ALLOW_CONCURRENT_WRITE=1 (headless CI, scripted setups).
private func guardNoConcurrentWriter() throws {
    if ProcessInfo.processInfo.environment["OPC_ALLOW_CONCURRENT_WRITE"] == "1" { return }
    let pgrep = Process()
    pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    pgrep.arguments = ["-x", "OPCCompany"]
    pgrep.standardOutput = FileHandle.nullDevice
    pgrep.standardError = FileHandle.nullDevice
    let appRunning: Bool
    do {
        try pgrep.run()
        pgrep.waitUntilExit()
        appRunning = pgrep.terminationStatus == 0
    } catch {
        appRunning = false  // no pgrep → no detection available
    }
    if appRunning {
        throw CLIError(message: "OPCCompany.app is running — the desktop app shares this snapshot "
            + "and last writer wins. Quit it first, or set OPC_ALLOW_CONCURRENT_WRITE=1 if you are "
            + "sure nothing else writes.")
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
                print("opc 0.2.0")
            case "status":
                try status()
            case "goal":
                try goal(rest)
            case "advance":
                try advance()
            case "report":
                try report()
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
}
