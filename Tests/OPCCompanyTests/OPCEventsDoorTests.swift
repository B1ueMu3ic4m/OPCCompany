import Foundation
import Testing

@testable import OPCCompanyCore

// v1.32 the `events_list` serializer: EVERY kind of event on the
// CURRENT product — the full stream the macOS EventLogView renders and
// no other front end could see — newest-first, capped at 50. Rows:
// {id, kind (raw enum value), title, detail, agentID?, createdAt}.
// Pins: the kind vocabulary rides verbatim, ties break by id, an empty
// office answers [], byte-stable repetition, the read leaves the write
// path byte-identical.

@MainActor
private func makeEventsSupport(_ name: String) throws -> URL {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    return supportDir
}

@MainActor
@Test func eventsDoorServesEveryKindNewestFirst() throws {
    let supportDir = try makeEventsSupport("opc-events-door")
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    let worker = store.agents.first!.id
    store.saveSnapshot()
    let seed = try Data(contentsOf: CompanyPersistence.stateURL)

    let base = Date(timeIntervalSince1970: 1_750_000_000)
    store.events = [
        CompanyEvent(productID: pid, kind: .risk, title: "风险", detail: "卡住",
                     agentID: worker,
                     createdAt: base.addingTimeInterval(30)),
        CompanyEvent(productID: pid, kind: .taskAssigned, title: "分配", detail: "领了",
                     createdAt: base.addingTimeInterval(20)),
        CompanyEvent(productID: pid, kind: .ctoSummary, title: "摘要", detail: "闭环 2",
                     createdAt: base.addingTimeInterval(10)),
        // an event from ANOTHER product must never ride this stream
        CompanyEvent(productID: UUID(), kind: .message, title: "别家", detail: "x",
                     createdAt: base.addingTimeInterval(60)),
    ]

    let d = try #require(JSONSerialization.jsonObject(with: try store.eventsListJSON()) as? [[String: Any]])
    #expect(d.count == 3, "the other product's event never rides: \(d.count)")
    #expect((d[0]["kind"] as? String) == "risk", "newest first: \(d.map { $0["kind"] })")
    #expect((d[1]["kind"] as? String) == "taskAssigned")
    #expect((d[2]["kind"] as? String) == "ctoSummary")
    #expect(d[0]["agentID"] as? String == worker.uuidString, "the agent link rides when present")
    #expect(d[1]["agentID"] == nil, "no fabricated owner")
    #expect(d[0]["createdAt"] as? Int == Int(base.addingTimeInterval(30).timeIntervalSince1970))
    #expect(d.map { $0["kind"] as? String ?? "" }
        .allSatisfy { ["risk", "taskAssigned", "ctoSummary"].contains($0) },
        "kind rides the RAW enum value — the snapshot's own vocabulary")

    // byte-stable repetition (sync body)
    #expect(try store.eventsListJSON() == store.eventsListJSON())

    // the pure read left the write path byte-identical
    #expect(try Data(contentsOf: CompanyPersistence.stateURL) == seed)
}

@MainActor
@Test func eventsDoorCapsAtFiftyAndBreaksTiesByID() throws {
    let supportDir = try makeEventsSupport("opc-events-cap")
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID

    let same = Date(timeIntervalSince1970: 1_750_000_000)
    store.events = (0..<80).map { i in
        CompanyEvent(productID: pid, kind: .statusChanged, title: "事件 \(i)",
                     detail: "load", createdAt: same)
    }

    let d = try #require(JSONSerialization.jsonObject(with: try store.eventsListJSON()) as? [[String: Any]])
    #expect(d.count == 50, "the stream caps at 50 under load: \(d.count)")
    let ids = d.compactMap { $0["id"] as? String }
    #expect(ids == ids.sorted(), "same-second ties break by id ASC — deterministic")
    let again = try #require(JSONSerialization.jsonObject(with: try store.eventsListJSON()) as? [[String: Any]])
    #expect(again.compactMap { $0["id"] as? String } == ids, "stable across calls")
}
