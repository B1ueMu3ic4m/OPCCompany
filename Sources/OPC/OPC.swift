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
//   opc standup [hours]     what happened in the window (traffic)
//   opc team [hours]        who did what in the window (traffic)
//   opc stalls [minutes]    what STOPPED moving and for how long
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
    opc — run your local AI company from the terminal. (v2.14.0)

    USAGE:
      opc status                 company snapshot (products, team, tasks, approvals)
      opc goal "TEXT"            send a boss goal to the CTO (creates the chain)
      opc advance                let the CTO advance every open goal one step
      opc autopilot [--cycles N] [--interval S] [--once]
                                 push the company forward N cycles (default 4)
                                 with S seconds between (default 30) — the same
                                 dispatch the app's autopilot drives; stops
                                 itself when an approval needs the boss or
                                 nothing moved. Boss-side writes.
      opc report                 boss-readable progress report (current product)
      opc approvals              list pending approvals with their ids
      opc decide <id> approve|reject
                                 resolve one pending approval (same store path
                                 as the GUI; refuses stale/double taps loudly)
      opc tell <agent> <line>    inject ONE line into an agent's live tmux
                                 seat on this machine — steer without leaving
                                 the terminal. <agent> is the uuid or the
                                 exact display name. Honest refusals: unknown
                                 name, no live seat, empty/oversize line.
      opc hall                   the terminal office on THIS machine, one
                                 honest paragraph: tmux present, workspace
                                 session state, per-agent seat liveness.
                                 Pure read: nothing here starts or stops.
      opc history [n]            last decisions of the current product —
                                 who asked, what you decided, when (default
                                 10). Pure read: nothing here writes state.
      opc deliverables [n]       the delivery shelf — what the company handed
                                 over, and whether each file still EXISTS on
                                 disk right now (default 10). Pure read.
      opc standup [HOURS]      what the company DID in the window
                                 (default 24) — traffic, not inventory.
                                 Pure read: nothing here writes state.
      opc team [HOURS]         WHO did what in the window (default 24)
                                 — per-employee attribution through real
                                 edges. Pure read: nothing here writes state.
      opc stalls [MINUTES]     what STOPPED moving: non-terminal work
                                 parked over [MINUTES] (default 30), longest
                                 first; approval-parked says WAITS ON YOU.
                                 Pure read: nothing here writes state.
      opc watch [SECONDS]      live view: one frame of the company every
                                 [SECONDS] (default 5) — the same doors the
                                 GUI quotes, restamped with the wall clock.
                                 Pure read. `opc watch --once` renders one
                                 frame and exits.
      opc desk <agent> [--json]  one employee's working surface — chips,
                                 session, assigned tasks, work queue,
                                 pending inbox. Pure read.
      opc transcript <agent> [--tail N] [--json]
                                 read an employee's visible terminal log —
                                 the same product-scoped, sanitized text
                                 the GUI's agent card shows, clipped to the
                                 last N lines (default 40, `--tail 0` =
                                 everything). Pure read.
      opc weight               how heavy the snapshot is RIGHT NOW —
                                 total bytes, the heaviest sections, and
                                 whether the maintenance advisory is
                                 crossed (same constant the GUI panel
                                 enforces). Pure read.
      opc catchup [HOURS] [MINUTES]
                                 one page that brings you up to speed —
                                 traffic, who did what, what's stuck, what
                                 waits on your desk, shelf integrity — the
                                 other doors composed, zero new math
                                 (defaults: 24h window, 30min stuck threshold).
                                 Pure read: nothing here writes state.
      opc products               list all products (ids included)
      opc use <id>               switch the selected product (same store path
                                 as the GUI sidebar; unknown ids refused)
      opc checkpoint <reason>    file a safety checkpoint — the same primitive
                                 the app runs before risky operations; the
                                 reason rides the record verbatim

    Read commands (status, approvals, history, deliverables, standup,
    team, stalls, catchup) accept --json: machine-readable output,
    byte-identical to what the FFI bridge serves the shell (one
    serializer, no drift).

    All commands read and write the same local company snapshot the desktop app
    uses, so CLI and GUI stay in sync. State lives under the OPC app-support
    directory (override with OPC_COMPANY_SUPPORT_DIR); nothing leaves your machine.
    """
}

/// v0.13.0 "the scriptable door": read verbs accept `--json` and print
/// the SAME bytes the bridge serves (CompanyStore+JSONDoors is the one
/// serializer) — pipe them into jq, diff them across time, drive
/// decisions from scripts. A `--json` read is still a pure read.
private func splitJSONFlag(_ rest: [String]) -> (Bool, [String]) {
    (rest.contains("--json"), rest.filter { $0 != "--json" })
}

@MainActor
private func printJSON(_ store: CompanyStore, _ data: Data) {
    print(String(decoding: data, as: UTF8.self))
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
                print("opc 2.14.0")
            case "status":
                try status(rest)
            case "goal":
                try goal(rest)
            case "advance":
                try advance()
            case "autopilot":
                try autopilot(rest)
            case "report":
                try report()
            case "approvals":
                try approvals(rest)
            case "decide":
                try decide(rest)
            case "tell":
                try tell(rest)
            case "hall":
                try hall(rest)
            case "history":
                try history(rest)
            case "deliverables":
                try deliverables(rest)
            case "standup":
                try standup(rest)
            case "team":
                try team(rest)
            case "stalls":
                try stalls(rest)
            case "catchup":
                try catchup(rest)
            case "weight":
                try weight(rest)
            case "watch":
                try watch(rest)
            case "transcript":
                try transcript(rest)
            case "desk":
                try desk(rest)
            case "products":
                try products()
            case "use":
                try use(rest)
            case "checkpoint":
                try checkpoint(rest)
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
    static func status(_ rest: [String]) throws {
        try withStore { store in
            let (json, _) = splitJSONFlag(rest)
            if json {
                // byte-for-byte what opc_bridge_snapshot_json serves the
                // shell — same shared serializer now
                guard let data = store.snapshotJSONData() else {
                    throw CLIError(message: "snapshot serialization failed")
                }
                printJSON(store, data)
                return
            }
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

    /// v2.9.0 "the autopilot": push the company forward cycle after cycle
    /// without the boss at the wheel — the SAME store primitive the
    /// desktop app's autopilot button drives (checkpoint, queue, blocked
    /// → approval, artifacts, verification, health audit, memory,
    /// advance — one full dispatch per cycle), one honest frame per
    /// cycle. The run stops ITSELF the moment it needs you: a pending
    /// approval pauses the loop (the terminal visitor never decides for
    /// the boss), and a cycle where nothing moved ends it honestly.
    /// `--cycles N` (default 4, 1–100), `--interval S` seconds between
    /// cycles (default 30, 1–3600), `--once` = exactly one cycle.
    @MainActor
    static func autopilot(_ rest: [String]) throws {
        var cycles = 4
        var interval = 30.0
        var index = 0
        while index < rest.count {
            let token = rest[index]
            if token == "--once" {
                cycles = 1
            } else if token == "--cycles", index + 1 < rest.count, let parsed = Int(rest[index + 1]) {
                cycles = parsed
                index += 1
            } else if token.hasPrefix("--cycles="), let parsed = Int(token.dropFirst("--cycles=".count)) {
                cycles = parsed
            } else if token == "--interval", index + 1 < rest.count, let parsed = Double(rest[index + 1]) {
                interval = parsed
                index += 1
            } else if token.hasPrefix("--interval="), let parsed = Double(token.dropFirst("--interval=".count)) {
                interval = parsed
            } else {
                throw CLIError(message: "usage: opc autopilot [--cycles N] [--interval S] [--once]")
            }
            index += 1
        }
        guard cycles >= 1, cycles <= 100 else {
            throw CLIError(message: "usage: opc autopilot [--cycles N] [--interval S] [--once]  (cycles 1–100, default 4)")
        }
        guard interval >= 1, interval <= 3600 else {
            throw CLIError(message: "usage: opc autopilot [--cycles N] [--interval S] [--once]  (interval 1–3600 seconds, default 30)")
        }
        try guardNoConcurrentWriter()
        print("Autopilot — \(cycles) cycle(s), \(Int(interval))s apart. The run stops itself the moment it needs the boss; Ctrl-C stops it sooner.")
        for cycle in 1...cycles {
            var needsBoss = false
            var moved = false
            try withStore { store in
                let statesBefore = store.tasks.map { "\($0.id):\($0.status.rawValue)" }.sorted()
                let queueBefore = store.workQueue.filter { $0.productID == store.selectedProductID }.count
                store.runCTOAutopilot()
                let statesAfter = store.tasks.map { "\($0.id):\($0.status.rawValue)" }.sorted()
                let queueAfter = store.workQueue.filter { $0.productID == store.selectedProductID }.count
                moved = statesBefore != statesAfter || queueBefore != queueAfter
                let pending = store.selectedProductPendingApprovals.count
                needsBoss = pending > 0
                print("\n── autopilot cycle \(cycle)/\(cycles) ──")
                print(watchFrame(store))
            }
            if needsBoss {
                print("\n  autopilot stops here: approval(s) are waiting on the boss — the loop never decides for you.")
                break
            }
            if !moved {
                print("\n  nothing moved this cycle — the office is quiet. stopping.")
                break
            }
            if cycle < cycles { Thread.sleep(forTimeInterval: interval) }
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
    static func approvals(_ rest: [String]) throws {
        try withStore { store in
            let (json, _) = splitJSONFlag(rest)
            if json {
                try printJSON(store, store.pendingApprovalsJSON())
                return
            }
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

    /// v0.18.0 "the tell door" — seat steering from the terminal: ONE
    /// line into an agent's live tmux seat. The same checked facade the
    /// bridge verb calls, so refusals are the store's own, verbatim.
    /// The agent may be named by uuid or exact display name
    /// (case-insensitive); ambiguity refuses rather than guesses.
    /// v2.4.0: `opc tell <agent> -` reads stdin to EOF and injects ONE
    /// line per input line — the seat semantics are one line at a time,
    /// so a multi-line paste is N honest sends, not one pretend one.
    /// The first refusal stops the run and names its line number.
    @MainActor
    static func tell(_ rest: [String]) throws {
        guard rest.count >= 2 else {
            throw CLIError(message: "usage: opc tell <agent> <line>  (or `opc tell <agent> -` to read stdin, one send per line; roster: opc team)")
        }
        let key = rest[0]
        let requested = rest.dropFirst().joined(separator: " ")
        try guardNoConcurrentWriter()
        try withStore { store in
            let agent = try resolveAgent(store, key)
            @MainActor
            func send(_ line: String) throws {
                do {
                    try store.terminalSendLine(agentID: agent.id, line: line)
                } catch let e as OPCBridgeRefusal {
                    throw CLIError(message: e.message)
                }
            }
            if requested == "-" {
                let data = FileHandle.standardInput.readDataToEndOfFile()
                var lines = String(decoding: data, as: UTF8.self)
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map(String.init)
                while let last = lines.last, last.isEmpty {
                    lines.removeLast() // the trailing newline is not a line
                }
                guard !lines.isEmpty else {
                    throw CLIError(message: "opc tell: stdin produced no lines")
                }
                for (index, line) in lines.enumerated() {
                    do {
                        try send(line)
                    } catch let e as CLIError {
                        throw CLIError(message: "line \(index + 1): \(e.message)")
                    }
                }
                print("→ \(agent.displayName) (\(lines.count) lines)")
            } else {
                try send(requested)
                print("→ \(agent.displayName)")
            }
        }
    }

    /// Shared agent resolution for the steering verbs (tell): uuid
    /// first, then exact display name (case-insensitive); an ambiguous
    /// name refuses rather than guessing.
    @MainActor
    static func resolveAgent(_ store: CompanyStore, _ key: String) throws -> CompanyAgent {
        if let id = UUID(uuidString: key),
           let known = store.agents.first(where: { $0.id == id }) {
            return known
        }
        let matches = store.agents.filter {
            $0.displayName.caseInsensitiveCompare(key) == .orderedSame
        }
        guard matches.count == 1 else {
            throw CLIError(message: matches.isEmpty
                ? "opc: no employee named '\(key)'  (roster: opc team)"
                : "opc: '\(key)' is ambiguous — \(matches.count) employees share that name")
        }
        return matches[0]
    }

    /// v2.4.0 the hall doctor: ONE honest paragraph about the terminal
    /// office on THIS machine — tmux present, workspace session state,
    /// per-agent seat liveness. Pure read (the `tmux ls` probe rides
    /// the core's process runner); nothing here starts or stops
    /// anything. Local pipe seats are named for what they are: facts
    /// of the office process that spawned them, invisible to a visitor.
    @MainActor
    static func hall(_ rest: [String]) throws {
        try withStore { store in
            let product = store.selectedProduct?.name ?? "— (no product yet)"
            print("Terminal hall — \(product)")

            if let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") {
                print("  tmux: \(tmuxPath)")
                let running = store.terminalWorkspaceSessionIsRunning()
                let session = store.terminalWorkspaceSessionNameForTesting()
                print("  workspace session: \(session) \(running ? "(running)" : "(not started)")")
            } else {
                print("  tmux: not found on this machine — tmux seats live elsewhere (local pipe seats are the other office's shape)")
            }

            print("  seats:")
            for agent in store.agents where agent.role != .boss {
                let open = store.hasOpenTerminalWindow(agentID: agent.id)
                let name = agent.displayName.prefix(20)
                print("    \(name)\(String(repeating: " ", count: max(1, 22 - name.count)))\(open ? "LIVE seat" : "no live seat")")
            }
            print("  local seats: none here (they are facts of the office process that spawned them — bridge verb: seat_list)")
        }
    }

    /// v0.6.0 "every hand leaves a receipt": the terminal's decision
    /// ledger — newest first, each row time-stamped and attributed to the
    /// employee who raised the hand. Read-only by construction (no
    /// guardNoConcurrentWriter: nothing writes).
    @MainActor
    static func history(_ rest: [String]) throws {
        let (json, args) = splitJSONFlag(rest)
        var limit = 10
        if let first = args.first {
            guard let parsed = Int(first), parsed > 0 else {
                throw CLIError(message: "usage: opc history [n]  (n — a positive count, default 10)")
            }
            limit = parsed
        }
        try withStore { store in
            if json { try printJSON(store, store.historyJSON()); return }
            let rows = store.selectedProductResolvedApprovals
            if rows.isEmpty {
                print("No decisions yet for \(store.selectedProduct?.name ?? "the selected product") — raised hands appear here once you approve or reject them.")
                return
            }
            let shown = rows.prefix(limit)
            print("Resolved approvals (\(shown.count) of \(rows.count)) — newest first:")
            for a in shown {
                let when = a.decidedAt.map { $0.opcDateTimeText } ?? "—"
                print("  \(a.id.uuidString)  \(a.status.title)  \(when)  ← \(store.requesterDisplayName(for: a))")
                print("    \(a.title) — \(a.reason)")
            }
        }
    }

    /// v0.7.0 "the delivery shelf": what did the company actually HAND
    /// OVER — and is it still on disk? The boss's last question. Reads the
    /// SAME delivery view the command center draws, stamps every row with
    /// the live existsOnDisk verdict; pure read, no side effects.
    @MainActor
    static func deliverables(_ rest: [String]) throws {
        let (json, args) = splitJSONFlag(rest)
        var limit = 10
        if let first = args.first {
            guard let parsed = Int(first), parsed > 0 else {
                throw CLIError(message: "usage: opc deliverables [n]  (n — a positive count, default 10)")
            }
            limit = parsed
        }
        try withStore { store in
            if json { try printJSON(store, store.deliverablesJSON()); return }
            let rows = store.selectedProductRecentDeliveryArtifacts
            if rows.isEmpty {
                print("No deliveries recorded for \(store.selectedProduct?.name ?? "the selected product") yet.")
                return
            }
            let shown = rows.prefix(limit)
            print("Deliverables (\(shown.count) of \(rows.count)) — newest first:")
            for a in shown {
                let mark = a.existsOnDisk ? "[OK] " : "[MISSING] "
                print("  \(mark)\(a.kind.title)  \(a.createdAt.opcDateTimeText)  \(a.title)")
                print("    \(a.path)")
            }
            let missing = rows.filter { !$0.existsOnDisk }.count
            if missing > 0 {
                print("\(missing) of \(rows.count) recorded deliveries have NO file on disk right now.")
            }
        }
    }

    /// v0.8.0 "the morning standup": what the company DID in the window
    /// (traffic), not what it HAS (status/report). Same pure-read promise
    /// as deliverables: no writer guard, nothing here writes state.
    @MainActor
    static func standup(_ rest: [String]) throws {
        let (json, args) = splitJSONFlag(rest)
        var hours = 24
        if let first = args.first {
            guard let parsed = Int(first), parsed > 0 else {
                throw CLIError(message: "usage: opc standup [hours]  (window in hours, default 24)")
            }
            hours = parsed
        }
        try withStore { store in
            if json { try printJSON(store, store.standupWindowJSON(hours: hours)); return }
            let w = store.standupWindow(hours: hours)
            let product = store.selectedProduct?.name ?? "the selected product"
            if w.quiet && w.awaitingNow == 0 {
                print("Standup — \(product): nothing in the last \(hours)h.")
                return
            }
            print("Standup — \(product), last \(hours)h:")
            print("  new work:      \(w.newWork)")
            print("  decided:       \(w.decisions)")
            print("  delivered:     \(w.deliveries)" + (w.missing > 0 ? "  (⚠ \(w.missing) MISSING on disk NOW)" : ""))
            print("  risks raised:  \(w.risks)")
            print("  awaiting you:  \(w.awaitingNow)" + (w.awaitingNow > 0 ? "  <- open the app or run: opc pending" : ""))
        }
    }

    @MainActor
    static func team(_ rest: [String]) throws {
        let (json, args) = splitJSONFlag(rest)
        var hours = 24
        if let first = args.first {
            guard let parsed = Int(first), parsed > 0 else {
                throw CLIError(message: "usage: opc team [hours]  (window in hours, default 24)")
            }
            hours = parsed
        }
        try withStore { store in
            if json { try printJSON(store, store.teamStatsJSON(hours: hours)); return }
            let rows = store.teamWindow(hours: hours)
            let product = store.selectedProduct?.name ?? "the selected product"
            if rows.isEmpty {
                print("Team — \(product): nobody moved in the last \(hours)h.")
                return
            }
            print("Team — \(product), last \(hours)h:")
            for r in rows {
                var parts: [String] = []
                if r.assigned > 0 { parts.append("\(r.assigned) assigned") }
                if r.deliveries > 0 {
                    parts.append("\(r.deliveries) delivered" + (r.missing > 0 ? " (\(r.missing) MISSING)" : ""))
                }
                if r.asked > 0 { parts.append("\(r.asked) approvals") }
                if r.risks > 0 { parts.append("\(r.risks) risks") }
                if r.activeNow > 0 { parts.append("\(r.activeNow) open now") }
                print("  " + r.name + ": " + (parts.isEmpty ? "—" : parts.joined(separator: ", ")))
            }
        }
    }

    @MainActor
    /// v0.10.0 "the stall watch": non-terminal work parked longer than
    /// [minutes] (default 30), longest first. Pure read — the door's own
    /// clock, no surface math.
    static func stalls(_ rest: [String]) throws {
        let (json, args) = splitJSONFlag(rest)
        var minutes = 30
        if let first = args.first {
            guard let parsed = Int(first), parsed > 0 else {
                throw CLIError(message: "usage: opc stalls [minutes]  (threshold in minutes, default 30)")
            }
            minutes = parsed
        }
        try withStore { store in
            if json { try printJSON(store, store.stallsJSON(overMinutes: minutes)); return }
            let rows = store.stallWatch(overMinutes: minutes)
            let product = store.selectedProduct?.name ?? "the selected product"
            if rows.isEmpty {
                print("Stalls — \(product): nothing parked over \(minutes) min.")
                return
            }
            print("Stalls — \(product), over \(minutes) min (longest first):")
            for r in rows {
                var line = "  \(r.dwellMinutes) min — \(r.status.rawValue)"
                line += r.waitingOnYou ? " (WAITS ON YOU)" : ""
                print(line + " — \(r.agentName)")
            }
        }
    }

    /// v0.11.0 "the catch-up": one page that brings the boss up to
    /// speed — traffic, who, stuck, your desk, shelf integrity — the
    /// store's own doors composed, zero new math. Pure read; the page
    /// is byte-stable for a given state (no wall-clock inside).
    @MainActor
    static func catchup(_ rest: [String]) throws {
        let (json, args) = splitJSONFlag(rest)
        var hours = 24
        var minutes = 30
        if let first = args.first {
            guard let parsed = Int(first), parsed > 0 else {
                throw CLIError(message: "usage: opc catchup [hours] [minutes]  (window hours, default 24; stuck threshold minutes, default 30)")
            }
            hours = parsed
        }
        if args.count > 1 {
            guard let parsed = Int(args[1]), parsed > 0 else {
                throw CLIError(message: "usage: opc catchup [hours] [minutes]  (window hours, default 24; stuck threshold minutes, default 30)")
            }
            minutes = parsed
        }
        try withStore { store in
            if json {
                try printJSON(store, store.catchupPageJSON(hours: hours, overMinutes: minutes))
                return
            }
            print(store.catchUpPage(hours: hours, overMinutes: minutes))
        }
    }

    /// v0.12.0 "the live office": one frame of the terminal live view.
    /// CLI surface, English prose (house rule) — but every NUMBER comes
    /// from the store's own doors (standupWindow / teamWindow /
    /// stallWatch / the pending queue), so a frame can never drift from
    /// what the GUI quotes. The wall-clock stamp belongs here: a live
    /// view IS about time; the doors themselves stay clockless.
    @MainActor
    static func watchFrame(_ store: CompanyStore, now: Date = Date()) -> String {
        let product = store.selectedProduct?.name ?? "— (no product yet)"
        let clock = Self.frameFormatter.string(from: now)
        var frame: [String] = []
        frame.append("OPC Company — \(product) · \(clock)")
        frame.append("  products: \(store.products.count)   employees: \(store.agents.count)")

        let scoped = store.tasks.filter { $0.productID == store.selectedProductID }
        if scoped.isEmpty {
            frame.append("  tasks: none yet — run: opc goal \"your first objective\"")
        } else {
            var counts: [String: Int] = [:]
            for t in scoped { counts[t.status.title, default: 0] += 1 }
            let line = counts.sorted { $0.value > $1.value }
                .map { "\($0.value) \($0.key)" }.joined(separator: ", ")
            frame.append("  tasks (\(scoped.count)): \(line)")
        }

        let w = store.standupWindow(now: now)
        var traffic: [String] = []
        if w.newWork > 0 { traffic.append("\(w.newWork) new") }
        if w.decisions > 0 { traffic.append("\(w.decisions) decided") }
        if w.deliveries > 0 {
            traffic.append("\(w.deliveries) delivered"
                + (w.missing > 0 ? " (\(w.missing) MISSING)" : ""))
        }
        if w.risks > 0 { traffic.append("\(w.risks) risk(s)") }
        frame.append("  last 24h: \(traffic.isEmpty ? "quiet" : traffic.joined(separator: " · "))")

        if let busiest = store.teamWindow(now: now).first {
            frame.append("  busiest: \(busiest.name) (traffic \(busiest.assigned + busiest.deliveries + busiest.asked + busiest.risks))")
        }

        let stalls = store.stallWatch(now: now)
        if stalls.isEmpty {
            frame.append("  stuck: nothing parked over 30 min")
        } else {
            let worst = stalls.first!
            frame.append("  stuck: \(stalls.count) parked over 30 min — worst \(worst.dwellMinutes) min \(worst.status.rawValue)\(worst.waitingOnYou ? " (WAITS ON YOU)" : "")")
        }

        let pending = store.selectedProductPendingApprovals.count
        frame.append("  awaiting you: \(pending) approval\(pending == 1 ? "" : "s")")

        // v2.5.0 the seats line: who has a physically open tmux window
        // RIGHT NOW — one list-windows probe feeds the whole frame.
        let open = store.openTerminalWindowAgentIDs()
        if open.isEmpty {
            frame.append("  seats: no windows open")
        } else {
            let names = store.agents
                .filter { open.contains($0.id) }
                .map { $0.displayName }
                .joined(separator: ", ")
            frame.append("  seats: \(open.count) open — \(names)")
        }
        return frame.joined(separator: "\n")
    }

    private static let frameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// The live view: clear + redraw every [seconds]. `--once` renders a
    /// single frame and exits — the seam tests pin without loops. Pure
    /// read: watching never writes state.
    @MainActor
    static func watch(_ rest: [String]) throws {
        var once = false
        var seconds = 5.0
        var args = rest
        if let i = args.firstIndex(of: "--once") {
            once = true
            args.remove(at: i)
        }
        if let first = args.first {
            guard let parsed = Double(first), parsed >= 1, parsed <= 3600 else {
                throw CLIError(message: "usage: opc watch [seconds] [--once]  (interval 1–3600, default 5)")
            }
            seconds = parsed
        }
        try withStore { store in
            let frame = watchFrame(store)
            // clear-once at startup, then redraw in place: a scrollback
            // full of cleared frames helps nobody (\u{1B}[H home, [2J clear)
            print("\u{1B}[H\u{1B}[2J")
            print(frame)
            if once { return }
            while true {
                Thread.sleep(forTimeInterval: seconds)
                print("\u{1B}[H\u{1B}[2J")
                print(watchFrame(store))
            }
        }
    }

    /// v2.6.0 "the transcript door" — read an employee's VISIBLE terminal
    /// log from the visitor's seat: the same product-scoped, sanitized,
    /// compacted text the GUI's agent card renders, clipped to the last
    /// `--tail N` lines (default 40; `--tail 0` serves everything).
    /// `--json` prints the bridge `transcript` verb's exact bytes. Pure
    /// read by construction — no guardNoConcurrentWriter, nothing writes.
    @MainActor
    static func transcript(_ rest: [String]) throws {
        var tail = 40
        var json = false
        var positional: [String] = []
        var index = 0
        while index < rest.count {
            let token = rest[index]
            if token == "--tail", index + 1 < rest.count, let parsed = Int(rest[index + 1]) {
                tail = parsed
                index += 1
            } else if token.hasPrefix("--tail="), let parsed = Int(token.dropFirst("--tail=".count)) {
                tail = parsed
            } else if token == "--json" {
                json = true
            } else {
                positional.append(token)
            }
            index += 1
        }
        guard let key = positional.first else {
            throw CLIError(message: "usage: opc transcript <agent> [--tail N] [--json]  (agent: uuid or exact display name; roster: opc team)")
        }
        try withStore { store in
            let agent = try resolveAgent(store, key)
            let data = try store.transcriptJSON(agentID: agent.id, tail: tail)
            if json {
                printJSON(store, data)
                return
            }
            let visible = store.visibleTerminalLog(for: agent.id)
            let lines = visible.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let window = tail > 0 ? lines.suffix(tail) : lines[...]
            print("\(agent.displayName) — transcript — \(window.count) of \(lines.count) lines")
            for line in window {
                print(line)
            }
        }
    }

    /// v0.15.0 "the weight door": scale without opinions — the total is
    /// the encoder's truth, the threshold is the maintenance panel's own
    /// constant, and the sections just say where the mass lives.
    @MainActor
    static func weight(_ rest: [String]) throws {
        try withStore { store in
            let (json, _) = splitJSONFlag(rest)
            let w = try store.snapshotWeightReport()
            if json {
                try printJSON(store, store.weightJSON())
                return
            }
            let product = store.selectedProduct?.name ?? "the selected product"
            print("Weight — \(product): \(Self.byteText(w.totalBytes))\(w.exceedsAdvisory ? "  ⚠ over advisory" : "")")
            print("  advisory: \(Self.byteText(w.advisoryBytes)) (the maintenance panel's own constant)")
            print("  terminal logs: \(Self.byteText(w.terminalLogBytes)) (\(w.logSharePercent)% of the snapshot)")
            for s in w.sections.prefix(5) {
                print("  \(Self.byteText(s.bytes).padding(toLength: 10, withPad: " ", startingAt: 0)) \(s.name)")
            }
            if w.sections.count > 5 { print("  ...and \(w.sections.count - 5) more sections") }
        }
    }

    @MainActor
    private static func byteText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
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

    /// v2.14.0 "the desk door": one employee's working surface from the
    /// visitor's seat — profile chips, session, assigned tasks, work
    /// queue, pending inbox — the SAME accessors the macOS agent desk
    /// renders, composed once. The agent may be named by uuid or exact
    /// display name; ambiguity refuses. \`--json\` serves the bridge
    /// \`desk\` verb's exact bytes. Pure read — the in-memory selection
    /// the composition needs is never saved.
    @MainActor
    static func desk(_ rest: [String]) throws {
        var json = false
        var positional: [String] = []
        for token in rest {
            if token == "--json" { json = true } else { positional.append(token) }
        }
        guard let key = positional.first else {
            throw CLIError(message: "usage: opc desk <agent> [--json]  (agent: uuid or exact display name; roster: opc team)")
        }
        try withStore { store in
            let agent = try resolveAgent(store, key)
            let data = try store.deskJSON(agentID: agent.id)
            if json {
                printJSON(store, data)
                return
            }
            let desk = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            print("\(agent.displayName) — desk (\(agent.role.title))")
            for chip in desk["profileChips"] as? [[String: Any]] ?? [] {
                let label = chip["label"] as? String ?? "?"
                if label == "会话" || label == "保活" { continue } // 专用会话段落覆盖
                print("  \(label): \(chip["value"] ?? "?")")
            }
            if let session = desk["session"] as? [String: Any] {
                print("  会话: \(session["state"] ?? "?") · \(session["capability"] ?? "?")")
            } else {
                print("  会话: 未运行")
            }
            let tasks = desk["assignedTasks"] as? [[String: Any]] ?? []
            print("  assigned tasks: \(tasks.count)")
            for task in tasks.prefix(5) {
                print("    · [\(task["status"] ?? "?")] \(task["title"] ?? "?")")
            }
            let queue = desk["workQueue"] as? [[String: Any]] ?? []
            print("  work queue: \(queue.count)")
            for item in queue.prefix(5) {
                print("    · [\(item["status"] ?? "?")] \(item["promptPreview"] ?? "?")")
            }
            if let pending = desk["pendingInboxCount"] as? Int {
                print("  pending inbox: \(pending)")
                for message in desk["pendingInbox"] as? [[String: Any]] ?? [] {
                    print("    · \(message["from"] ?? "?") → \(message["subject"] ?? "?")")
                }
            }
        }
    }

    /// v2.12.0 "the checkpoint door": the boss files a safety checkpoint
    /// from the terminal — the same store primitive the app runs before
    /// every risky operation (cleanup, reset, product deletion,
    /// autopilot). The reason rides the record verbatim; an empty reason
    /// refuses; a checkpoint that failed to land reports failure and
    /// exits nonzero (the checked facade reads the verdict — no silent
    /// no-ops). Boss-side write.
    @MainActor
    static func checkpoint(_ rest: [String]) throws {
        let reason = rest.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !reason.isEmpty else {
            throw CLIError(message: "usage: opc checkpoint <reason>  (e.g. `opc checkpoint before migrating the task graph`)")
        }
        try guardNoConcurrentWriter()
        try withStore { store in
            guard store.createSafetyCheckpointChecked(reason: reason) else {
                throw CLIError(message: "checkpoint failed to land — the risk event names the error")
            }
            let dir = CompanyPersistence.stateURL.deletingLastPathComponent()
                .appendingPathComponent("checkpoints", isDirectory: true)
            let count = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil))?
                .filter { $0.lastPathComponent.hasPrefix("checkpoint-") }.count ?? 0
            print("✓ checkpoint filed (\(count) on disk) — reason: \(reason)")
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
