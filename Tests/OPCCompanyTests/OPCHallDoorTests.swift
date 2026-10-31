import Foundation
import Testing

@testable import OPCCompanyCore

// v1.28 `hall` at the serializer: the tmux workspace facts on this
// machine. Pins (machine-independent — never hard-coded absolutes): the
// facts COHERED with the same accessors the CLI text and GUI chip use;
// ONE probe feeds every seat row (rows match openTerminalWindowAgentIDs);
// local pipe seats are deliberately absent; byte-stable repetition; the
// pure-read promise holds.

@MainActor
@Test func hallDoorReportsFactsCoherently() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-hall-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let seededBytes = try Data(contentsOf: CompanyPersistence.stateURL)

    let data = try store.hallJSON()
    let d = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(d["tmuxAvailable"] as? Bool ==
        (AgentProcessRunner.resolvedExecutablePath(for: "tmux") != nil))
    let tmuxAvailable = d["tmuxAvailable"] as? Bool == true
    if tmuxAvailable {
        #expect(d["tmuxPath"] is String, "a found tmux names its path")
    } else {
        #expect(d["tmuxPath"] is NSNull, "no tmux, no path — honest null")
    }
    #expect(d["sessionName"] as? String ==
        store.terminalWorkspaceSessionNameForTesting())
    #expect(d["sessionRunning"] as? Bool == store.terminalWorkspaceSessionIsRunning())

    // seat rows: every non-boss agent, liveness from ONE probe
    let seats = try #require(d["seats"] as? [[String: Any]])
    #expect(seats.count == store.agents.filter { $0.role != .boss }.count)
    let openNow = store.openTerminalWindowAgentIDs()
    for row in seats {
        #expect(row["agentID"] is String && row["name"] is String
                && row["open"] is Bool)
        #expect((row["open"] as? Bool) == openNow.contains(UUID(uuidString: row["agentID"] as! String)!))
    }
    #expect(!seats.contains { ($0["name"] as? String) == "总技术负责人" },
            "the boss keeps no seat row")

    // byte-stable repetition (sync body: nothing moved between calls)
    #expect(try store.hallJSON() == data)

    // the query left the write path clean
    #expect(try Data(contentsOf: CompanyPersistence.stateURL) == seededBytes)
}
