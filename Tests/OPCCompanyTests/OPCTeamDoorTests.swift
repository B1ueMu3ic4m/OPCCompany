import Foundation
import Testing

@testable import OPCCompanyCore

// The v0.9.0 team door: attribution through REAL edges (event.agentID,
// approval.requesterID, artifact -task-> owner), never a guess. Dead
// ends land in the named unattributed row; the unattributed row sorts
// last; the window math reuses the v0.8 discipline.

@MainActor
private func teamSeeded(now: Date) -> (CompanyStore, UUID, UUID) {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    let alice = store.agents.first!.id
    let bob = store.agents[1].id
    store.events = [
        CompanyEvent(productID: pid, kind: .taskAssigned, title: "e", detail: "d",
                     agentID: alice, createdAt: now.addingTimeInterval(-3600)),
        CompanyEvent(productID: pid, kind: .taskAssigned, title: "e", detail: "d",
                     agentID: bob, createdAt: now.addingTimeInterval(-1800)),
        CompanyEvent(productID: pid, kind: .risk, title: "e", detail: "d",
                     agentID: alice, createdAt: now.addingTimeInterval(-900)),
        // 25h ago — outside a 24h window
        CompanyEvent(productID: pid, kind: .taskAssigned, title: "e", detail: "d",
                     agentID: alice, createdAt: now.addingTimeInterval(-25 * 3600)),
        // other product's traffic
        CompanyEvent(productID: UUID(), kind: .taskAssigned, title: "e", detail: "d",
                     agentID: alice, createdAt: now.addingTimeInterval(-600)),
    ]
    store.approvals = [
        ApprovalRequest(productID: pid, requesterID: alice, title: "a", reason: "r",
                        status: .approved, decidedAt: now.addingTimeInterval(-600)),
    ]
    return (store, alice, bob)
}

@Test @MainActor func teamWindowAttributesThroughRealEdges() throws {
    let tmp = try temporarySupportDir("team-math")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let now = Date(timeIntervalSince1970: 1_760_000_000)
    let (store, alice, bob) = teamSeeded(now: now)

    // deliveries ride the TASK CHAIN: artifact -> task -> owner
    let real = tmp.appendingPathComponent("ship.md")
    try "x".data(using: .utf8)!.write(to: real)
    let ghost = tmp.appendingPathComponent("ghost").path
    var tAlice = CompanyTask(productID: store.selectedProductID, title: "TA",
                             ownerID: alice, status: .running, successCriteria: "s")
    var tNil = CompanyTask(productID: store.selectedProductID, title: "TN",
                           ownerID: nil, status: .running, successCriteria: "s")
    store.tasks = [tAlice, tNil]
    _ = bob // bob's bucket comes from an event, not a task
    store.artifacts = [
        ArtifactRecord(productID: store.selectedProductID, taskID: tAlice.id, kind: .report,
                       title: "在", path: real.path, summary: "s",
                       createdAt: now.addingTimeInterval(-900)),
        ArtifactRecord(productID: store.selectedProductID, taskID: tAlice.id, kind: .report,
                       title: "没", path: ghost, summary: "s",
                       createdAt: now.addingTimeInterval(-900)),
        // task with nil owner -> dead end -> unattributed row
        ArtifactRecord(productID: store.selectedProductID, taskID: tNil.id, kind: .report,
                       title: "链断", path: real.path, summary: "s",
                       createdAt: now.addingTimeInterval(-900)),
        // artifact with NO task at all -> also unattributed
        ArtifactRecord(productID: store.selectedProductID, taskID: nil, kind: .report,
                       title: "孤", path: real.path, summary: "s",
                       createdAt: now.addingTimeInterval(-900)),
    ]

    let rows = store.teamWindow(hours: 24, now: now)
    let a = try #require(rows.first { $0.agentID == alice })
    let b = try #require(rows.first { $0.agentID == bob })
    let u = try #require(rows.first { $0.agentID == nil })

    // window + scope math (mirrors the v0.8 red lines)
    #expect(a.assigned == 1, "25h and other-product assignments must not leak: \(a)")
    #expect(a.risks == 1 && a.asked == 1)
    #expect(a.deliveries == 2 && a.missing == 1,
            "existence rides the SAME door as v0.7: \(a)")
    #expect(b.assigned == 1 && b.traffic == 1)
    #expect(u.deliveries == 2, "dead-chain + orphan artifacts are ONE honest row: \(u)")
    #expect(u.name == "未分配", "the bucket is named, never personified: \(u.name)")

    // ordering contract: unattributed LAST regardless of counts
    #expect(rows.last?.agentID == nil, "boss reads names first: \(rows.map(\.name))")
    // traffic desc among people
    let people = rows.filter { $0.agentID != nil }
    #expect(people.first?.agentID == alice, "alice (traffic 4) outranks bob (1)")

    // widen the window: the 25h assignment joins alice
    let wide = store.teamWindow(hours: 48, now: now)
    #expect(wide.first { $0.agentID == alice }?.assigned == 2)
}

@Test @MainActor func teamWindowIsPureAndStaleIdsHonest() throws {
    let tmp = try temporarySupportDir("team-pure")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let now = Date(timeIntervalSince1970: 1_760_000_000)
    let (store, alice, _) = teamSeeded(now: now)

    // a stale agent id in an event: named 未知员工, never dropped, never guessed
    let ghostID = UUID()
    store.events.append(CompanyEvent(productID: store.selectedProductID,
                                     kind: .taskAssigned, title: "e", detail: "d",
                                     agentID: ghostID, createdAt: now.addingTimeInterval(-300)))
    let rows = store.teamWindow(hours: 24, now: now)
    let g = try #require(rows.first { $0.agentID == ghostID })
    #expect(g.name == "未知员工", "a stale id is named honestly: \(g.name)")

    // pure read: two calls answer identically, support dir untouched
    let before = try FileManager.default.contentsOfDirectory(atPath: tmp.path)
    let again = store.teamWindow(hours: 24, now: now)
    #expect(again == rows, "same door, same answer")
    let after = try FileManager.default.contentsOfDirectory(atPath: tmp.path)
    #expect(before == after, "the team door never writes")
}

@Test @MainActor func teamQuietCompanyAnswersEmptyRows() throws {
    let tmp = try temporarySupportDir("team-quiet")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.events = []
    store.approvals = []
    store.artifacts = []
    let rows = store.teamWindow()
    // a bootstrap company carries seeded roster + maybe seeded queue; the
    // promise is only: no phantom buckets and everyone present is real.
    #expect(rows.allSatisfy { $0.agentID != nil }, "no traffic, no unattributed row")
}

// The GUI/CLI headline sentence quotes the SAME door the rows come from:
// shape pinned, numbers as slots — no wall-clock luck, no drift between
// surfaces (the v0.8 standupHeadline test's discipline, replayed).
@Test @MainActor func teamHeadlineQuotesTheSameDoor() throws {
    let tmp = try temporarySupportDir("team-headline")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let now = Date()
    let pid = store.selectedProductID
    let alice = store.agents.first!.id
    store.events = [
        CompanyEvent(productID: pid, kind: .taskAssigned, title: "e", detail: "d",
                     agentID: alice, createdAt: now.addingTimeInterval(-600)),
        CompanyEvent(productID: pid, kind: .taskAssigned, title: "e", detail: "d",
                     agentID: alice, createdAt: now.addingTimeInterval(-600)),
    ]
    store.tasks = []
    store.artifacts = []
    store.approvals = []

    let rows = store.teamWindow(now: now)
    let line = store.teamHeadlineText(now: now)
    let top = rows.first!
    #expect(line.contains(top.name), "the busiest name is quoted: \(line)")
    #expect(line.contains("\(top.traffic)"), "the number slot matches the door: \(line)")

    // unattributed traffic is FLAGGED, not hidden: a dead task chain
    // (artifact -> nonexistent task) lands in the named bucket
    store.artifacts = [
        ArtifactRecord(productID: pid, taskID: UUID(), kind: .report,
                       title: "o", path: tmp.appendingPathComponent("x").path,
                       summary: "s", createdAt: now.addingTimeInterval(-600)),
    ]
    let flagged = store.teamHeadlineText(now: now)
    #expect(flagged.contains("未归属"), "the headline admits the orphan: \(flagged)")
}

private func temporarySupportDir(_ tag: String) throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("opc-\(tag)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
