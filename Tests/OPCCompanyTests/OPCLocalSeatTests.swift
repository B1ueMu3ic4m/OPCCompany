import Foundation
import Testing

@testable import OPCCompanyCore

// v2.0.0 local seats (Option B phase 2) — the keep-stdin office. Pinned:
// a /bin/cat seat round-trips (line in → transcript out → clean stop),
// every refusal is honest (unknown agent, API employee, one-shot codex,
// double spawn, steering/stopping a seat that isn't there), terminal_send
// routes to the local seat when tmux has nothing, the interactive command
// builder is honest per backend, and the v1.12 bridge verbs carry the
// lifecycle over the real ABI.

@MainActor
private func makeSeatAgent(_ store: CompanyStore, name: String,
                           command: String,
                           backendType: BackendType = .subscriptionCLI) throws -> CompanyAgent {
    var draft = EmployeeDraft()
    draft.displayName = name
    draft.command = command
    draft.backendType = backendType
    store.addEmployee(from: draft)
    guard let agent = store.agents.first(where: { $0.displayName == name }) else {
        throw OPCBridgeRefusal(message: "test seed failed: \(name) missing")
    }
    return agent
}

@MainActor @Test func localSeatRoundTripsThroughTheTranscript() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let agent = try makeSeatAgent(store, name: "SeatCat", command: "/bin/cat")

    try store.spawnLocalSeat(agentID: agent.id)
    #expect(store.hasLiveLocalSeat(agentID: agent.id))

    try store.sendLocalSeatLine(agentID: agent.id, line: "seat-marker-alpha")
    var transcript = ""
    for _ in 0..<50 {
        transcript = store.currentProductTerminalLog(for: agent.id)
        if transcript.contains("seat-marker-alpha") { break }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    #expect(transcript.contains("seat-marker-alpha"),
            "the seat's echo must land in the per-seat transcript: \(transcript.suffix(300))")

    try store.stopLocalSeat(agentID: agent.id)
    #expect(!store.hasLiveLocalSeat(agentID: agent.id),
            "stop forgets the registry entry — a stopped seat is no fact of this store")
    // double stop refuses
    do {
        try store.stopLocalSeat(agentID: agent.id)
        Issue.record("double stop must refuse")
    } catch let e as OPCBridgeRefusal {
        #expect(e.message.contains("no local seat"))
    }
}

@MainActor @Test func localSeatsRefuseHonestly() throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cat = try makeSeatAgent(store, name: "SeatCat", command: "/bin/cat")
    let codex = try makeSeatAgent(store, name: "CodexGuy", command: "codex")
    let api = try makeSeatAgent(store, name: "ApiGuy", command: "irrelevant",
                                backendType: .api)
    let stranger = UUID()

    // unknown agent
    do {
        try store.spawnLocalSeat(agentID: stranger)
        Issue.record("unknown agent must refuse")
    } catch let e as OPCBridgeRefusal {
        #expect(e.message.contains("no agent with id"))
    }
    // one-shot-only backend (codex: TUI needs a TTY)
    do {
        try store.spawnLocalSeat(agentID: codex.id)
        Issue.record("codex must refuse")
    } catch let e as OPCBridgeRefusal {
        #expect(e.message.contains("one-shot"))
    }
    // API employees have no CLI seat
    do {
        try store.spawnLocalSeat(agentID: api.id)
        Issue.record("api employee must refuse")
    } catch let e as OPCBridgeRefusal {
        #expect(e.message.contains("not a CLI employee"))
    }
    // steering / stopping a seat that was never spawned
    do {
        try store.sendLocalSeatLine(agentID: cat.id, line: "hello")
        Issue.record("send without a seat must refuse")
    } catch let e as OPCBridgeRefusal {
        #expect(e.message.contains("no live local seat"))
    }
    do {
        try store.stopLocalSeat(agentID: cat.id)
        Issue.record("stop without a seat must refuse")
    } catch let e as OPCBridgeRefusal {
        #expect(e.message.contains("no local seat"))
    }

    // double spawn refuses, and the FIRST seat stays alive and steerable
    try store.spawnLocalSeat(agentID: cat.id)
    do {
        try store.spawnLocalSeat(agentID: cat.id)
        Issue.record("double spawn must refuse")
    } catch let e as OPCBridgeRefusal {
        #expect(e.message.contains("already has a live local seat"))
    }
    #expect(store.hasLiveLocalSeat(agentID: cat.id))
    try store.stopLocalSeat(agentID: cat.id)
}

@MainActor @Test func terminalSendSteersTheLocalSeat() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let agent = try makeSeatAgent(store, name: "TellCat", command: "/bin/cat")

    // no tmux workspace was started: terminal_send must fall through to
    // the local pipe seat (v2.0.0 — one verb, whichever office)
    try store.spawnLocalSeat(agentID: agent.id)
    try store.terminalSendLine(agentID: agent.id, line: "tell-marker-bravo")
    var transcript = ""
    for _ in 0..<50 {
        transcript = store.currentProductTerminalLog(for: agent.id)
        if transcript.contains("tell-marker-bravo") { break }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    #expect(transcript.contains("tell-marker-bravo"),
            "terminal_send must reach the local seat: \(transcript.suffix(300))")
    try store.stopLocalSeat(agentID: agent.id)

    // with NO seat at all, the v1.11 refusal wording stays stable
    do {
        try store.terminalSendLine(agentID: agent.id, line: "nobody there")
        Issue.record("send without any seat must refuse")
    } catch let e as OPCBridgeRefusal {
        #expect(e.message.contains("no live tmux seat"))
    }
}

@MainActor @Test func interactiveCommandShapesAreHonest() throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    var claude = EmployeeDraft()
    claude.displayName = "CC"
    claude.command = "claude"
    claude.model = "sonnet"
    store.addEmployee(from: claude)
    let claudeAgent = store.agents.first { $0.displayName == "CC" }!
    let claudeCommand = CLIAgentCommandBuilder.interactiveCommand(for: claudeAgent)
    #expect(claudeCommand?.first == "claude")
    #expect(claudeCommand?.contains("--permission-mode") == true)
    #expect(claudeCommand?.contains("sonnet") == true)

    var gemini = EmployeeDraft()
    gemini.displayName = "GG"
    gemini.command = "gemini"
    gemini.model = ""
    store.addEmployee(from: gemini)
    let geminiAgent = store.agents.first { $0.displayName == "GG" }!
    #expect(CLIAgentCommandBuilder.interactiveCommand(for: geminiAgent)?.first == "gemini")

    // custom commands pass through bare; codex and API refuse
    let catAgent = store.agents.first { $0.displayName == "SeatlessCat" }
    #expect(catAgent == nil)
    var custom = EmployeeDraft()
    custom.displayName = "Custom"
    custom.command = "/bin/cat"
    store.addEmployee(from: custom)
    let customAgent = store.agents.first { $0.displayName == "Custom" }!
    #expect(CLIAgentCommandBuilder.interactiveCommand(for: customAgent) == ["/bin/cat"])

    var codex = EmployeeDraft()
    codex.displayName = "CX"
    codex.command = "codex"
    store.addEmployee(from: codex)
    let codexAgent = store.agents.first { $0.displayName == "CX" }!
    #expect(CLIAgentCommandBuilder.interactiveCommand(for: codexAgent) == nil)

    var api = EmployeeDraft()
    api.displayName = "API"
    api.backendType = .api
    store.addEmployee(from: api)
    let apiAgent = store.agents.first { $0.displayName == "API" }!
    #expect(CLIAgentCommandBuilder.interactiveCommand(for: apiAgent) == nil)
}

@MainActor @Test func bridgeSeatLifecycleOverRealABI() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("opc-seat-bridge-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    setenv("OPC_COMPANY_SUPPORT_DIR", tmp.path, 1)
    defer { unsetenv("OPC_COMPANY_SUPPORT_DIR") }

    // seed IN-PROCESS before create, so the bridge's store sees this roster
    let seedStore = CompanyStore.bootstrap(loadPersisted: false)
    var draft = EmployeeDraft()
    draft.displayName = "BridgeCat"
    draft.command = "/bin/cat"
    seedStore.addEmployee(from: draft)
    seedStore.saveSnapshot()
    guard let agent = seedStore.agents.first(where: { $0.displayName == "BridgeCat" }) else {
        Issue.record("seed failed")
        return
    }
    let payload = "{\"agentID\":\"\(agent.id.uuidString)\"}"

    #expect(opc_bridge_create() == 0)
    defer { opc_bridge_destroy() }

    func runVerb(_ verb: String, _ json: String) -> (rc: Int32, reason: String) {
        let v = strdup(verb)
        let p = strdup(json)
        defer { free(v); free(p) }
        let rc = opc_bridge_command(v, p)
        let reason = opc_bridge_last_error().map { String(cString: $0) } ?? ""
        return (rc, reason)
    }

    let spawned = runVerb("seat_spawn", payload)
    #expect(spawned.rc == 0, "seat_spawn must succeed: \(spawned.reason)")
    #expect(spawned.reason.isEmpty, "a write's success is silence")

    let double = runVerb("seat_spawn", payload)
    #expect(double.rc == -1 && double.reason.contains("already has a live local seat"),
            "double spawn must refuse: \(double.reason)")

    // v1.12: terminal_send now reaches the bridge's own local seat too
    let tell = runVerb("terminal_send",
                       "{\"agentID\":\"\(agent.id.uuidString)\",\"line\":\"bridge-marker\"}")
    #expect(tell.rc == 0, "terminal_send must steer the local seat: \(tell.reason)")

    let stopped = runVerb("seat_stop", payload)
    #expect(stopped.rc == 0, "seat_stop must succeed: \(stopped.reason)")

    let again = runVerb("seat_stop", payload)
    #expect(again.rc == -1 && again.reason.contains("no local seat"),
            "stopping twice must refuse: \(again.reason)")
}

// MARK: - v2.2.0 the readable seat

@Test func ansiNormalizerStripsEscapeSequencesAndCarriesPartialOnes() {
    let normalizer = ANSIStreamNormalizer()

    // SGR colors stripped, text kept
    #expect(normalizer.feed("\u{1B}[31mred\u{1B}[0m plain\n") == "red plain\n")

    // OSC window title stripped whole
    #expect(normalizer.feed("\u{1B}]0;my title\u{07}body\n") == "body\n")

    // a CSI split across pipe chunks degrades into nothing, not garbage
    #expect(normalizer.feed("ok \u{1B}[3") == "ok ")
    #expect(normalizer.feed("3mhidden\u{1B}[0m tail\n") == "hidden tail\n")

    // C0 control bytes (BEL etc.) dropped, \n and \t kept
    #expect(normalizer.feed("a\u{07}b\tc\nd\n") == "ab\tc\nd\n")

    // flush drains the carry (a dangling ESC at end-of-stream)
    #expect(normalizer.feed("tail \u{1B}") == "tail ")
    #expect(normalizer.flush() == "")
    #expect(normalizer.feed("after\n") == "after\n")
}

@MainActor @Test func localSeatTranscriptStaysReadableThroughANSI() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    var draft = EmployeeDraft()
    draft.displayName = "AnsiCat"
    draft.command = "/bin/cat"
    store.addEmployee(from: draft)
    guard let agent = store.agents.first(where: { $0.displayName == "AnsiCat" }) else {
        Issue.record("seed failed")
        return
    }

    try store.spawnLocalSeat(agentID: agent.id)
    // the seat ECHOES what we steer: feed it ANSI exactly like a real
    // interactive CLI would emit — the transcript must stay readable
    try store.sendLocalSeatLine(agentID: agent.id, line: "\u{1B}[32mansi-marker\u{1B}[0m done")
    var transcript = ""
    for _ in 0..<50 {
        transcript = store.currentProductTerminalLog(for: agent.id)
        if transcript.contains("ansi-marker") { break }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    #expect(transcript.contains("ansi-marker"),
            "the marker must survive: \(transcript.suffix(300))")
    #expect(!transcript.contains("\u{1B}"),
            "no escape byte may reach the transcript: \(transcript.suffix(300))")
    try store.stopLocalSeat(agentID: agent.id)
}

// MARK: - v2.3.0 the seat roster

@MainActor @Test func localSeatRosterReportsLivenessAndForgetStops() throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let agent = try makeSeatAgent(store, name: "RosterCat", command: "/bin/cat")

    // no seats: the honest empty office
    #expect(store.localSeatStatuses().isEmpty)

    try store.spawnLocalSeat(agentID: agent.id)
    #expect(store.localSeatStatuses() == [agent.id: true])

    // an exited-but-not-stopped seat stays in the roster, honestly false
    if let process = store.localSeatProcesses[agent.id] {
        process.stop()
    }
    #expect(store.localSeatStatuses() == [agent.id: false])

    // an explicit stop forgets the entry entirely
    try store.stopLocalSeat(agentID: agent.id)
    #expect(store.localSeatStatuses().isEmpty)
}

@MainActor @Test func bridgeSeatRosterOverRealABI() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("opc-seatlist-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    setenv("OPC_COMPANY_SUPPORT_DIR", tmp.path, 1)
    defer { unsetenv("OPC_COMPANY_SUPPORT_DIR") }

    let seedStore = CompanyStore.bootstrap(loadPersisted: false)
    var draft = EmployeeDraft()
    draft.displayName = "ListCat"
    draft.command = "/bin/cat"
    seedStore.addEmployee(from: draft)
    seedStore.saveSnapshot()
    guard let agent = seedStore.agents.first(where: { $0.displayName == "ListCat" }) else {
        Issue.record("seed failed")
        return
    }
    let payload = "{\"agentID\":\"\(agent.id.uuidString)\"}"

    #expect(opc_bridge_create() == 0)
    defer { opc_bridge_destroy() }

    func runVerb(_ verb: String, _ json: String?) -> (rc: Int32, reason: String) {
        let v = strdup(verb)
        let p = json.flatMap { strdup($0) }
        defer { free(v); free(p) }
        let rc = opc_bridge_command(v, p)
        let reason = opc_bridge_last_error().map { String(cString: $0) } ?? ""
        return (rc, reason)
    }

    // empty office: {} rides the channel
    let empty = runVerb("seat_list", nil)
    #expect(empty.rc == 0 && empty.reason == "{}", "empty roster must be {}: \(empty.reason)")

    let spawned = runVerb("seat_spawn", payload)
    #expect(spawned.rc == 0, "spawn must succeed: \(spawned.reason)")

    let roster = runVerb("seat_list", nil)
    #expect(roster.rc == 0)
    let decoded = try JSONSerialization.jsonObject(with: Data(roster.reason.utf8))
    let map = try #require(decoded as? [String: Bool])
    #expect(map == [agent.id.uuidString: true], "roster must carry liveness: \(roster.reason)")

    #expect(runVerb("seat_stop", payload).rc == 0)
    let afterStop = runVerb("seat_list", nil)
    #expect(afterStop.rc == 0 && afterStop.reason == "{}",
            "a stopped seat has no entry: \(afterStop.reason)")
}
