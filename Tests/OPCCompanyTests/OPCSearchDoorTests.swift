import Foundation
import Testing

@testable import OPCCompanyCore

// v1.24 `search` at the serializer: ONE keyword across four surfaces.
// Pins: hits land from every surface that matches, each naming its door;
// the match is case-insensitive substring; the drill filter holds
// (drills never surface); ordering is newest-first with id tiebreak;
// empty refuses, zero hits answers []; the limit knob caps; pure read.

@MainActor
@Test func searchDoorSpansSurfacesAndFiltersDrills() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-search-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    let alice = store.agents.first!.id
    let realFile = supportDir.appendingPathComponent("goals-door.md")
    try "shipped".data(using: .utf8)!.write(to: realFile)
    store.tasks = [
        CompanyTask(productID: pid, title: "实现 goals 门", ownerID: alice,
                    status: .running, successCriteria: "读出链"),
    ]
    store.artifacts = [
        ArtifactRecord(productID: pid, taskID: store.tasks[0].id, kind: .report,
                       title: "goals 门报告", path: realFile.path, summary: "s"),
    ]
    store.postAgentMessage(productID: pid, fromAgentID: store.ctoID,
                           toAgentID: alice, taskID: nil,
                           kind: .taskDispatched,
                           subject: "派发：goals 门", body: "见任务卡",
                           persist: false)
    store.postAgentMessage(productID: pid, fromAgentID: store.ctoID,
                           toAgentID: alice, taskID: nil,
                           kind: .reviewRequested,
                           subject: "[演练] goals 门闭合演练", body: "drill",
                           persist: false)
    store.events = [
        CompanyEvent(productID: pid, kind: .risk, title: "goals 门编译失败",
                     detail: "seeded"),
    ]

    let data = try store.searchJSON(query: "GOALS 门")
    let rows = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    let kinds = rows.compactMap { $0["kind"] as? String }
    #expect(kinds.contains("task") && kinds.contains("artifact")
            && kinds.contains("message") && kinds.contains("event"),
            "one keyword, every surface answers: \(kinds)")
    #expect(!rows.contains { ($0["title"] as? String)?.contains("演练") == true },
            "the drill filter holds on the search surface too")
    #expect(rows.allSatisfy { ($0["id"] is String) && ($0["createdAt"] is Int) })
    #expect(rows[0]["createdAt"] as? Int ?? 0 >= rows[1]["createdAt"] as? Int ?? 0,
            "newest first")

    // byte-stable repetition (sync body)
    #expect(try store.searchJSON(query: "GOALS 门") == data)

    // the read left the write path clean
    let seeded = try Data(contentsOf: CompanyPersistence.stateURL)
    _ = try store.searchJSON(query: "goals 门")
    #expect(try Data(contentsOf: CompanyPersistence.stateURL) == seeded)
}

@MainActor
@Test func searchDoorRefusesEmptyAndAnswersZeroHonestly() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-search-empty-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    #expect(throws: OPCBridgeRefusal.self) {
        try store.searchJSON(query: "   ")
    }
    let rows = try #require(JSONSerialization.jsonObject(
        with: try store.searchJSON(query: "nothing-matches-this")) as? [[String: Any]])
    #expect(rows.isEmpty, "zero hits answers [] — never a fake row")

    // the limit knob caps
    let pid = store.selectedProductID
    for i in 0..<5 {
        store.events.append(CompanyEvent(productID: pid, kind: .risk,
                                         title: "hit \(i)", detail: "",
                                         createdAt: Date().addingTimeInterval(Double(-i))))
    }
    let capped = try #require(JSONSerialization.jsonObject(
        with: try store.searchJSON(query: "hit", limit: 2)) as? [[String: Any]])
    #expect(capped.count == 2)
}
