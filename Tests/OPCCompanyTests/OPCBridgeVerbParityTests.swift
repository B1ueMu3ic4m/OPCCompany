import Foundation
import Testing

@testable import OPCCompanyCore

// The contract-parity gate: "every door one face" as a TEST, not a
// habit. The bridge's switch is the verb truth; the Flutter shell must
// face every verb except the documented exemptions and must never call
// a verb the bridge lacks; the CLI's alias map must resolve against the
// bridge. The v1.25 batch ack rode ten versions without a shell face —
// this gate exists so the next orphan cannot.

let parityRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

func paritySource(_ relative: String) throws -> String {
    try String(contentsOf: parityRoot.appendingPathComponent(relative),
               encoding: .utf8)
}

func verbLiterals(in text: String, pattern: String) throws -> Set<String> {
    let re = try NSRegularExpression(pattern: pattern)
    let ns = text as NSString
    var out = Set<String>()
    for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
        out.insert(ns.substring(with: m.range(at: 1)))
    }
    return out
}

/// The bridge's verb switch IS the ABI truth: every `case "verb":` in
/// OPCBridge.swift (the file has no other string-case switch).
func abiVerbSet() throws -> Set<String> {
    try verbLiterals(in: paritySource("Sources/OPCCompanyCore/OPCBridge.swift"),
                     pattern: #"case "([a-z_]+)":"#)
}

/// The shell's verb literals: every `command('verb')`, `_listVerb('verb')`
/// and `_seatWrite('verb')` in the bindings — the three call shapes a
/// wrapper can use.
func shellVerbSet() throws -> Set<String> {
    let src = try paritySource("flutter_shell/lib/opc_bridge_bindings.dart")
    var out = Set<String>()
    for pat in [#"\bcommand\(\s*'([a-z_]+)'"#,
                #"_listVerb\(\s*'([a-z_]+)'"#,
                #"_seatWrite\(\s*'([a-z_]+)'"#] {
        out.formUnion(try verbLiterals(in: src, pattern: pat))
    }
    return out
}

@Test func theShellFacesEveryBridgeVerbOrNamesItsExemption() throws {
    let abi = try abiVerbSet()
    #expect(abi.count >= 30,
            "the bridge switch is the verb truth — scanned \(abi.count) cases; if this drops, the extraction regex rotted")

    let shell = try shellVerbSet()

    // no phantom calls: the shell never names a verb the bridge lacks
    #expect(shell.isSubset(of: abi),
            "shell calls verbs the bridge doesn't have: \(shell.subtracting(abi).sorted())")

    // every door a face. Exemptions are DOCUMENTED, one line each:
    // - hall (v1.28): live-seat probing — the shell runs on machines
    //   where the Mac's tmux is not; a probe would lie. Honest "—".
    let exempt: Set<String> = ["hall"]
    let orphan = abi.subtracting(shell).subtracting(exempt)
    #expect(orphan.isEmpty,
            "ABI verbs without a shell face — surface them in the shell or extend the documented exemption with a reason: \(orphan.sorted())")
    #expect(exempt.isSubset(of: abi),
            "the exemption list may only name real bridge verbs")
}

@Test func cliAliasMapResolvesAgainstTheBridge() throws {
    let abi = try abiVerbSet()

    // The CLI's public names are the contract's human face; each maps
    // to exactly one bridge verb (verified against OPC.swift's dispatch
    // and its verb functions). CLI-only composites (status/report/watch/
    // help/version) touch many verbs and are out of scope here.
    let cliAliases: [String: String] = [
        "goal": "goal",
        "advance": "advance",
        "autopilot": "autopilot",
        "checkpoint": "checkpoint",
        "checkpoints": "checkpoints_list",
        "decide": "decide",
        "desk": "desk",
        "doctor": "doctor",
        "hall": "hall",
        "goals": "goals_list",
        "risks": "risks_list",
        "messages": "messages_list",
        "task": "task_show",
        "search": "search",
        "ack": "message_ack",
        "approvals": "approvals_list",
        "history": "history_list",
        "deliverables": "deliverables_list",
        "standup": "standup_window",
        "team": "team_stats_list",
        "stalls": "stalls_list",
        "catchup": "catchup_md",
        "weight": "weight_json",
        "products": "products_list",
        "use": "product_select",
        "tell": "terminal_send",
        "transcript": "transcript",
        "events": "events_list",
    ]

    let dead = cliAliases.filter { !abi.contains($0.value) }
    #expect(dead.isEmpty,
            "CLI aliases point at verbs the bridge doesn't have: \(dead.keys.sorted())")
}
