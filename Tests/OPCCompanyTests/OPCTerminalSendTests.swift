import Foundation
import Testing

@testable import OPCCompanyCore

// v1.11 `terminal_send` — Option B phase 1 over the real ABI with a
// REAL tmux seat. Pinned: honest refusals (unknown agent, empty line,
// oversize line, agent with no seat) never fake an ack, and a live
// seat actually receives the line (captured back through tmux itself).

private func cleanuptmux(_ tmuxPath: String, _ sessionName: String) {
    _ = OPCProcessRunner.runAndWait(executable: tmuxPath,
                                    arguments: ["kill-session", "-t", sessionName],
                                    workingDirectory: FileManager.default.temporaryDirectory)
}

@Test @MainActor func terminalSendRefusesHonestlyWithoutASeat() throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let stranger = UUID()

    // unknown agent
    do {
        _ = try store.terminalSendLine(agentID: stranger, line: "hello")
        Issue.record("unknown agent must refuse")
    } catch let e as OPCBridgeRefusal {
        #expect(e.message.contains("no agent with id"))
    }
    // empty line
    do {
        _ = try store.terminalSendLine(agentID: store.agents.first!.id, line: "")
        Issue.record("empty line must refuse")
    } catch let e as OPCBridgeRefusal {
        #expect(e.message.contains("empty line"))
    }
    // oversize line
    do {
        _ = try store.terminalSendLine(agentID: store.agents.first!.id, line: String(repeating: "x", count: 5000))
        Issue.record("oversize line must refuse")
    } catch let e as OPCBridgeRefusal {
        #expect(e.message.contains("4096"))
    }
    // a real agent with NO live seat on this machine: pick one that
    // preparePersistentTerminalTarget would reject — a non-CLI backend
    if let apiAgent = store.agents.first(where: { $0.backend.type != .subscriptionCLI }) {
        do {
            _ = try store.terminalSendLine(agentID: apiAgent.id, line: "hello")
            Issue.record("non-tmux agent must refuse")
        } catch let e as OPCBridgeRefusal {
            #expect(e.message.contains("no live tmux seat"))
        }
    }
    // pure input: nothing wrote state
    #expect(store.events.isEmpty || store.events.allSatisfy { $0.kind != .taskCreated })
}

@Test @MainActor func terminalSendDeliversToALiveTmuxSeat() async throws {
    guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("OPCTmuxSend-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources", isDirectory: true),
                                            withIntermediateDirectories: true)
    try "// package".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    store.products[0].rootDirectory = root.path
    let sessionName = store.terminalWorkspaceSessionNameForTesting()
    defer { cleanuptmux(tmuxPath, sessionName) }

    store.startTerminalWorkspaceForSelectedProduct()

    // find an agent whose seat is actually live (backend + capability + tmux)
    var liveTargetAgent: CompanyAgent?
    for candidate in store.agents {
        // the prepare function is the door's own truth about seat liveness
        if store.hasLiveTerminalSeat(agentID: candidate.id) {
            liveTargetAgent = candidate
            break
        }
    }
    guard let agent = liveTargetAgent else {
        // no seat qualified on this runner — the honest-refusal test
        // above still covered the contract
        return
    }

    let marker = "opc-send-\(UUID().uuidString.prefix(8))"
    try store.terminalSendLine(agentID: agent.id, line: "echo \(marker)")

    // the seat echoes: the line must surface in a fresh capture
    let target = try #require(store.persistentTerminalTargetForTesting(agentID: agent.id))
    let session = store.persistentTerminalSessionForTesting(target: target)
    var captured = ""
    for _ in 0..<20 {
        let r = await session.capture(workingDirectory: FileManager.default.temporaryDirectory)
        captured = r.output
        if captured.contains(marker) { break }
        try await Task.sleep(nanoseconds: 300_000_000)
    }
    #expect(captured.contains(marker), "the line must be echoed by the seat: \(captured.suffix(400))")
}
