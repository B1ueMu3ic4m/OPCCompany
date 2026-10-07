import Foundation
import Testing

@testable import OPCCompanyCore

// v1.19 `goals_list` at the serializer: the goal ledger. Pins: a started
// goal lands as ONE row with its four-task chain, the six closure steps,
// and the linked-edge counts; a company with no goals answers [] honestly;
// repetition is byte-stable (order IS the contract for a list); and the
// pure-read promise holds (the ledger never moves the snapshot it reads).

private func rowsFrom(_ data: Data) throws -> [[String: Any]] {
    try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
}

@MainActor
@Test func goalsDoorListsTheLedgerWithTheFullChain() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-goals-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    #expect(try rowsFrom(try store.goalsListJSON()).isEmpty,
            "an office with no goals answers [] — never a fake row")

    let ctoTaskID = store.startCTOSupervisorGoal(goal: "ship the doctor door")
    #expect(ctoTaskID != nil, "a default roster can start a goal")
    let seededBytes = try Data(contentsOf: CompanyPersistence.stateURL)

    let data = try store.goalsListJSON()
    let rows = try rowsFrom(data)
    #expect(rows.count == 1, "one goal, one row: \(rows)")
    let row = rows[0]
    #expect(row["goal"] as? String == "ship the doctor door")
    #expect(row["goalID"] is String)
    #expect(["passed", "warning", "failed"].contains(row["status"] as? String))
    #expect(row["completionScore"] is Int)
    #expect(row["createdAt"] is Int && row["updatedAt"] is Int,
            "dates ride epoch seconds like every other list door")

    let steps = try #require(row["steps"] as? [[String: Any]])
    #expect(steps.count == 6, "task-graph, message-bus, cto-loop, approval, review-gate, evidence: \(steps.map { $0["id"] })")
    #expect(steps.allSatisfy { ($0["id"] is String) && ($0["title"] is String)
            && (["passed", "warning", "failed"].contains($0["status"] as? String))
            && ($0["detail"] is String) })

    let counts = try #require(row["counts"] as? [String: Any])
    #expect(counts["tasks"] as? Int == 4,
            "the chain is cto + engineer + reviewer + boss: \(counts)")
    #expect((counts["messages"] as? Int ?? 0) >= 1,
            "the goal-started message is a real edge: \(counts)")

    // byte-stable repetition (sync body: nothing moved between calls)
    #expect(try store.goalsListJSON() == data, "same ledger, same bytes")

    // the read left the write path clean
    #expect(try Data(contentsOf: CompanyPersistence.stateURL) == seededBytes)
}

@MainActor
@Test func goalsDoorKeepsTwoGoalsDistinct() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-goals-two-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    #expect(store.startCTOSupervisorGoal(goal: "first goal") != nil)
    #expect(store.startCTOSupervisorGoal(goal: "second goal") != nil)

    let rows = try rowsFrom(try store.goalsListJSON())
    #expect(rows.count == 2, "two starts, two chains — never merged: \(rows.map { $0["goal"] })")
    let goals = rows.compactMap { $0["goal"] as? String }
    #expect(goals.contains("first goal") && goals.contains("second goal"))
    // newest-touched first: the ledger orders by updatedAt, ties by goal
    #expect(rows[0]["updatedAt"] as? Int ?? 0 >= rows[1]["updatedAt"] as? Int ?? 0)
}
