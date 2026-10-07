import Foundation
import Testing

@testable import OPCCompanyCore

// v1.21 `messages_list` at the serializer: the message bus. Pins: the
// product's recent traffic lands newest-first with RESOLVED display
// names; closure drills never surface; kind/status/taskID ride the
// envelope; byte-stable order (createdAt desc, ties by id — the
// accessor's own discipline); an honest office answers []; pure read.

@MainActor
private func seedBus(now: Date) -> CompanyStore {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    let cto = store.ctoID
    let alice = store.agents.first!.id
    store.postAgentMessage(productID: pid, fromAgentID: cto, toAgentID: alice,
                           taskID: nil, kind: .taskDispatched,
                           subject: "派发：实现 goals 门",
                           body: "见任务卡", persist: false)
    store.postAgentMessage(productID: pid, fromAgentID: alice, toAgentID: cto,
                           taskID: nil, kind: .workCompleted,
                           subject: "回传：goals 门已实现",
                           body: "已交付", persist: false)
    store.postAgentMessage(productID: pid, fromAgentID: cto, toAgentID: alice,
                           taskID: nil, kind: .reviewRequested,
                           subject: "[演练] 闭合演练审查",
                           body: "a drill never rides the bus",
                           persist: false)
    return store
}

@MainActor
@Test func messagesDoorListsTheBusNewestFirstWithResolvedNames() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-bus-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = seedBus(now: Date())
    store.saveSnapshot()
    let seededBytes = try Data(contentsOf: CompanyPersistence.stateURL)

    let data = try store.messagesListJSON()
    let rows = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    #expect(rows.count == 2, "the drill never rides the bus: \(rows.map { $0["subject"] })")
    #expect(rows[0]["subject"] as? String == "回传：goals 门已实现", "newest first")
    #expect(rows[0]["from"] as? String == store.agents.first!.displayName,
            "from arrives RESOLVED, not as a uuid")
    #expect(rows[0]["to"] as? String != nil, "to arrives resolved too")
    #expect(rows[0]["kind"] as? String == "workCompleted")
    #expect(rows[0]["status"] as? String == "pending")
    #expect(rows[0]["createdAt"] is Int)
    #expect(rows.allSatisfy { $0["id"] is String && $0["subject"] is String })

    // byte-stable repetition: same bus, same bytes
    #expect(try store.messagesListJSON() == data)

    // the read left the write path clean
    #expect(try Data(contentsOf: CompanyPersistence.stateURL) == seededBytes)
}

@MainActor
@Test func messagesDoorAnswersEmptyHonestly() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-bus-empty-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    #expect(try (JSONSerialization.jsonObject(
        with: try store.messagesListJSON()) as? [[String: Any]] ?? []).isEmpty,
        "a quiet bus answers [] — never a fake message")
}
