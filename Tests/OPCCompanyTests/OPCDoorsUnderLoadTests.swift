import Foundation
import Testing

@testable import OPCCompanyCore

// The doors under load: a REAL company at scale — hundreds of events,
// messages, tasks, approvals — every list door still answers LEGAL
// JSON, still honors its cap, still sorts honestly. NO timing
// assertions: a shared CI box wobbles; the caps and the order are the
// contract, not the clock. Every test also pins that a pure-read door
// left the write path byte-identical.

@MainActor
private func makeLoadedSupport() throws -> URL {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-load-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    return supportDir
}

@MainActor
private func seededBytes() throws -> Data {
    try Data(contentsOf: CompanyPersistence.stateURL)
}

@MainActor
@Test func messagesDoorUnderLoadCapsAndSortsHonestly() throws {
    let supportDir = try makeLoadedSupport()
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    let sender = store.agents.first!.id
    store.saveSnapshot()
    let seed = try seededBytes()

    let base = Date(timeIntervalSince1970: 1_750_000_000)
    var envelopes: [AgentMessageEnvelope] = []
    for i in 0..<300 {
        var m = AgentMessageEnvelope(productID: pid, fromAgentID: sender,
                                     toAgentID: store.agents.last?.id,
                                     kind: .taskDispatched,
                                     subject: "批量消息 \(i)",
                                     body: "load",
                                     createdAt: base.addingTimeInterval(TimeInterval(i)))
        m.createdAt = base.addingTimeInterval(TimeInterval(i))
        envelopes.append(m)
    }
    store.agentMessages = envelopes

    let rows = try rowsFromJSON(store.messagesListJSON())
    #expect(rows.count == 50, "the bus caps at 50 under load: \(rows.count)")
    let times = rows.compactMap { $0["createdAt"] as? Int }
    #expect(times == times.sorted(by: >),
            "newest-first survives the load: \(times.prefix(5))…")
    #expect(times.first == Int(base.addingTimeInterval(299).timeIntervalSince1970),
            "the newest envelope leads — nothing younger got cut in line")

    // the pure read left the write path byte-identical
    #expect(try seededBytes() == seed)
}

@MainActor
private func rowsFromJSON(_ data: Data) throws -> [[String: Any]] {
    let rows = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    return rows
}

@MainActor
@Test func risksDoorUnderLoadCapsAndSortsHonestly() throws {
    let supportDir = try makeLoadedSupport()
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    store.saveSnapshot()
    let seed = try seededBytes()

    let base = Date(timeIntervalSince1970: 1_750_000_000)
    store.events = (0..<120).map { i in
        CompanyEvent(productID: pid, kind: .risk,
                     title: "规模风险 \(i)", detail: "load",
                     createdAt: base.addingTimeInterval(TimeInterval(i)))
    }

    let rows = try rowsFromJSON(store.risksListJSON())
    #expect(rows.count == 50, "the risk ledger caps at 50 under load: \(rows.count)")
    let times = rows.compactMap { $0["createdAt"] as? Int }
    #expect(times == times.sorted(by: >), "newest-first survives the load")
    #expect(times.first == Int(base.addingTimeInterval(119).timeIntervalSince1970),
            "the newest risk leads")
    #expect(rows.allSatisfy { ($0["title"] as? String)?.hasPrefix("规模风险") == true },
            "rows are the seeded events — nothing fabricated to fill the cap")

    #expect(try seededBytes() == seed)
}

@MainActor
@Test func historyDoorUnderLoadCapsAtFifty() throws {
    let supportDir = try makeLoadedSupport()
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    let requester = store.agents.first!.id
    store.saveSnapshot()
    let seed = try seededBytes()

    let base = Date(timeIntervalSince1970: 1_750_000_000)
    var approvals: [ApprovalRequest] = []
    for i in 0..<80 {
        var a = ApprovalRequest(productID: pid, requesterID: requester,
                                title: "已批 \(i)", reason: "load",
                                status: .approved)
        a.decidedAt = base.addingTimeInterval(TimeInterval(i))
        approvals.append(a)
    }
    store.approvals = approvals

    let rows = try rowsFromJSON(store.historyJSON())
    #expect(rows.count == 50, "the decision ledger caps at 50 under load: \(rows.count)")
    let times = rows.compactMap { $0["decidedAt"] as? Int }
    #expect(times == times.sorted(by: >), "newest-decided-first survives the load")
    #expect(times.first == Int(base.addingTimeInterval(79).timeIntervalSince1970))

    #expect(try seededBytes() == seed)
}

@MainActor
@Test func searchDoorUnderLoadClampsItsLimitBothWays() throws {
    let supportDir = try makeLoadedSupport()
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    let owner = store.agents.first!.id
    store.saveSnapshot()
    let seed = try seededBytes()

    var tasks: [CompanyTask] = []
    for i in 0..<200 {
        let title = i < 60 ? "needle 任务 \(i)" : "普通任务 \(i)"
        var t = CompanyTask(productID: pid, title: title, ownerID: owner,
                            status: .running, successCriteria: "s")
        tasks.append(t)
    }
    store.tasks = tasks

    // default limit: 30 hits of the 60 that match
    let defaultRows = try rowsFromJSON(store.searchJSON(query: "needle"))
    #expect(defaultRows.count == 30, "the default search cap holds: \(defaultRows.count)")
    // an oversized ask clamps to 50
    let clamped = try rowsFromJSON(store.searchJSON(query: "needle", limit: 500))
    #expect(clamped.count == 50, "an oversized ask clamps to the 50 ceiling: \(clamped.count)")
    // a zero ask clamps up to at least one — never an accidental empty page
    let floored = try rowsFromJSON(store.searchJSON(query: "needle", limit: 0))
    #expect(!floored.isEmpty, "limit 0 clamps up: \(floored.count) rows")

    #expect(try seededBytes() == seed)
}

@MainActor
@Test func goalsDoorUnderLoadCapsAtTwentyAcrossManyChains() throws {
    let supportDir = try makeLoadedSupport()
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)

    let seededNames = Set((0..<30).map { "规模目标 \($0)" })
    for name in seededNames {
        #expect(store.startCTOSupervisorGoal(goal: name) != nil)
    }
    // the 30 starts are WRITES — persist them, then pin the read as pure
    store.saveSnapshot()
    let seed = try seededBytes()

    let rows = try rowsFromJSON(store.goalsListJSON())
    #expect(rows.count == 20, "the goal ledger caps at 20 across 30 chains: \(rows.count)")
    let goals = rows.compactMap { $0["goal"] as? String }
    #expect(Set(goals).count == 20, "capped rows are distinct chains: \(goals.prefix(5))")
    #expect(Set(goals).isSubset(of: seededNames),
            "every capped row is one of the seeded chains — nothing fabricated: \(goals)")
    let times = rows.compactMap { $0["updatedAt"] as? Int }
    #expect(times == times.sorted(by: >),
            "newest-touched first survives the load (ties may share a second)")

    // byte-stable repetition under load (sync door)
    let again = try rowsFromJSON(store.goalsListJSON())
    #expect(again.map { $0["goal"] as? String } == goals, "stable across calls")

    #expect(try seededBytes() == seed)
}

@MainActor
@Test func snapshotDoorUnderLoadAnswersLegalJSONAtScale() throws {
    let supportDir = try makeLoadedSupport()
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    let owner = store.agents.first!.id

    var tasks: [CompanyTask] = []
    for i in 0..<200 {
        tasks.append(CompanyTask(productID: pid, title: "规模任务 \(i)",
                                 ownerID: owner, status: .running,
                                 successCriteria: "s"))
    }
    store.tasks = tasks
    store.events = (0..<150).map { i in
        CompanyEvent(productID: pid, kind: .risk, title: "规模风险 \(i)",
                     detail: "load")
    }
    store.saveSnapshot()
    let seed = try seededBytes()

    let snap = try #require(store.snapshotJSONData())
    let d = try #require(JSONSerialization.jsonObject(with: snap) as? [String: Any])
    #expect(d["schemaVersion"] as? Int == 14,
            "the schema version rides the big snapshot too")
    let agents = try #require(d["agents"] as? [[String: Any]])
    #expect(agents.count == store.agents.count,
            "the roster survives the scale: \(agents.count)")
    let snapTasks = try #require(d["tasks"] as? [[String: Any]])
    #expect(snapTasks.count == 200,
            "all 200 tasks ride the snapshot: \(snapTasks.count)")
    let snapEvents = try #require(d["events"] as? [[String: Any]])
    #expect(snapEvents.count == 150,
            "all 150 events ride the snapshot: \(snapEvents.count)")

    // shape-stable repetition: the snapshot carries LIVE fields (agent
    // dwell clocks are recomputed per call), so under a full-suite run
    // the bytes legitimately drift between two calls — the CONTRACT is
    // the shape (schema, roster, counts), not the clock.
    let again = try #require(store.snapshotJSONData())
    let d2 = try #require(JSONSerialization.jsonObject(with: again) as? [String: Any])
    #expect(d2["schemaVersion"] as? Int == 14)
    #expect((d2["tasks"] as? [[String: Any]])?.count == 200)
    #expect((d2["events"] as? [[String: Any]])?.count == 150)

    // the pure read left the write path byte-identical
    #expect(try seededBytes() == seed)
}
