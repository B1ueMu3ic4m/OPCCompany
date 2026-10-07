import Foundation
import Testing

@testable import OPCCompanyCore

// v1.20 `risks_list` at the serializer: the risk ledger. Pins: risk
// events land newest-first with their agent link; the boss-view filter
// is REAL (closure drills and whitelisted backend noise never appear);
// order is byte-stable (createdAt desc, ties by id); an honest office
// answers []; and the pure-read promise holds.

@MainActor
private func seedRisks(now: Date) -> CompanyStore {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    let alice = store.agents.first!.id
    store.events = [
        CompanyEvent(productID: pid, kind: .risk, title: "编译失败：主链路",
                     detail: "模块 A 编译错误", agentID: alice,
                     createdAt: now.addingTimeInterval(-600)),
        CompanyEvent(productID: pid, kind: .risk, title: "命令行作业档案写入失败",
                     detail: "backend noise — the whitelist keeps it from the boss",
                     agentID: alice,
                     createdAt: now.addingTimeInterval(-300)),
        CompanyEvent(productID: pid, kind: .risk, title: "[演练] 闭合演练",
                     detail: "a drill is not a risk the boss must read",
                     agentID: alice,
                     createdAt: now.addingTimeInterval(-120)),
        CompanyEvent(productID: pid, kind: .risk, title: "审查驳回",
                     detail: "reviewer sent it back", agentID: nil,
                     createdAt: now.addingTimeInterval(-60)),
    ]
    return store
}

@MainActor
@Test func risksDoorListsTheBossViewNewestFirst() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-risks-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let now = Date()
    let store = seedRisks(now: now)
    store.saveSnapshot()
    let seededBytes = try Data(contentsOf: CompanyPersistence.stateURL)

    let data = try store.risksListJSON()
    let rows = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    #expect(rows.count == 2, "the drill and the whitelisted backend noise never reach the boss: \(rows.map { $0["title"] })")
    #expect(rows[0]["title"] as? String == "审查驳回", "newest first: \(rows.map { $0["title"] })")
    #expect(rows[0]["agentID"] == nil, "an unattributed risk keeps no agent key")
    #expect(rows[1]["agentID"] != nil, "an attributed risk carries its agent")
    #expect(rows[0]["createdAt"] is Int, "dates ride epoch seconds")
    #expect(rows.allSatisfy { ($0["id"] is String) && ($0["title"] is String) && ($0["detail"] is String) })

    // byte-stable repetition: same ledger, same bytes
    #expect(try store.risksListJSON() == data)

    // the read left the write path clean
    #expect(try Data(contentsOf: CompanyPersistence.stateURL) == seededBytes)
}

@MainActor
@Test func risksDoorOrdersTiesByIdAndAnswersEmptyHonestly() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-risks-tie-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    #expect(try (JSONSerialization.jsonObject(
        with: try store.risksListJSON()) as? [[String: Any]] ?? []).isEmpty,
        "a quiet office answers [] — never a fake row")

    let pid = store.selectedProductID
    let stamp = Date()
    store.events = [
        CompanyEvent(id: UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000002")!, productID: pid, kind: .risk, title: "b", detail: "", createdAt: stamp),
        CompanyEvent(id: UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001")!, productID: pid, kind: .risk, title: "a", detail: "", createdAt: stamp),
    ]
    let rows = try #require(JSONSerialization.jsonObject(
        with: try store.risksListJSON()) as? [[String: Any]])
    #expect((rows[0]["id"] as? String)?.hasSuffix("0001") == true,
            "same timestamp → id order, so the bytes never wobble: \(rows.map { $0["id"] })")
}
