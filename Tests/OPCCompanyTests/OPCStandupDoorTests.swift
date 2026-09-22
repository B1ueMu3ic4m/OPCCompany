import Foundation
import Testing

@testable import OPCCompanyCore

// The v0.8.0 traffic door: the window is REAL math over three sources,
// scoped like every other surface (current product), honest about
// legacy rows, and the MISSING intersection rides v0.7's existence
// door rather than re-deriving it.

@MainActor
private func seededStore(now: Date) -> CompanyStore {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    let other = UUID()
    store.events = [
        CompanyEvent(productID: pid, kind: .taskCreated, title: "新活", detail: "d", createdAt: now.addingTimeInterval(-3600)),
        CompanyEvent(productID: pid, kind: .risk, title: "风险", detail: "d", createdAt: now.addingTimeInterval(-7200)),
        CompanyEvent(productID: pid, kind: .statusChanged, title: "杂项", detail: "d", createdAt: now.addingTimeInterval(-3600)),
        // 25h ago — one hour OUTSIDE a 24h window, must not count
        CompanyEvent(productID: pid, kind: .taskCreated, title: "旧活", detail: "d", createdAt: now.addingTimeInterval(-25 * 3600)),
        // another product's traffic — same kind, same window: excluded
        CompanyEvent(productID: other, kind: .taskCreated, title: "别人家的活", detail: "d", createdAt: now.addingTimeInterval(-1800)),
    ]
    store.approvals = [
        ApprovalRequest(productID: pid, title: "批", reason: "r", status: .approved,
                        decidedAt: now.addingTimeInterval(-600)),
        ApprovalRequest(productID: pid, title: "等", reason: "r", status: .pending),
        // decided WITHOUT decidedAt (pre-v0.6 legacy): honest exclusion
        ApprovalRequest(productID: pid, title: "旧批", reason: "r", status: .approved,
                        decidedAt: nil),
    ]
    return store
}

@Test @MainActor func standupWindowIsRealScopedMath() throws {
    let tmp = try temporarySupportDir("standup-math")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let now = Date(timeIntervalSince1970: 1_760_000_000)

    let store = seededStore(now: now)
    // delivery window rides the existence door: one real file, one ghost
    let real = tmp.appendingPathComponent("ship.md")
    try "x".data(using: .utf8)!.write(to: real)
    store.artifacts = [
        ArtifactRecord(productID: store.selectedProductID, kind: .report,
                       title: "在", path: real.path, summary: "s",
                       createdAt: now.addingTimeInterval(-900)),
        ArtifactRecord(productID: store.selectedProductID, kind: .report,
                       title: "没", path: tmp.appendingPathComponent("ghost").path,
                       summary: "s", createdAt: now.addingTimeInterval(-900)),
        // yesterday's delivery — outside the window even though on disk
        ArtifactRecord(productID: store.selectedProductID, kind: .report,
                       title: "前天", path: real.path, summary: "s",
                       createdAt: now.addingTimeInterval(-48 * 3600)),
    ]

    let w = store.standupWindow(hours: 24, now: now)
    #expect(w.newWork == 1, "25h-old and other-product creations must not leak in: \(w)")
    #expect(w.risks == 1)
    #expect(w.decisions == 1, "the decidedAt-less legacy receipt must not be guessed: \(w)")
    #expect(w.deliveries == 2, "both window deliveries count; the 48h one must not")
    #expect(w.missing == 1, "MISSING rides the SAME existence door as the shelf")
    #expect(w.awaitingNow == 1, "the live queue is not windowed")
    #expect(!w.quiet)

    // widen the window: yesterday's work comes in — the window is real math
    let wide = store.standupWindow(hours: 48, now: now)
    #expect(wide.newWork == 2 && wide.deliveries == 3)

    // the door writes NOTHING: no save, no support-dir touch required
    #expect(store.events.count == 5 && store.approvals.count == 3)
}

@Test @MainActor func standupQuietCompanySaysSo() throws {
    let tmp = try temporarySupportDir("standup-quiet")
    defer { try? FileManager.default.removeItem(at: tmp) }
    setenv("OPC_COMPANY_SUPPORT_DIR", tmp.path, 1)
    defer { unsetenv("OPC_COMPANY_SUPPORT_DIR") }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let w = store.standupWindow()
    #expect(w.quiet, "a company that did nothing must answer nothing, not noise")
    #expect(w.awaitingNow == 0)
}

@Test @MainActor func standupHeadlineQuotesTheSameDoor() throws {
    let tmp = try temporarySupportDir("standup-headline")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let now = Date(timeIntervalSince1970: 1_760_000_000)
    setenv("OPC_COMPANY_SUPPORT_DIR", tmp.path, 1)
    defer { unsetenv("OPC_COMPANY_SUPPORT_DIR") }

    let store = seededStore(now: now)
    let line = store.standupHeadlineText(hours: 24, now: now)
    // seeded: 1 new work, 1 decision, 1 risk, 1 awaiting — numbers ride
    // OUTSIDE the l10n fragments, three surfaces quote this one sentence
    #expect(line.contains("1 项新工作"), "seeded new work must be quoted: \(line)")
    #expect(line.contains("1 个决定"), "seeded decision must be quoted: \(line)")
    #expect(line.contains("1 条风险"), "seeded risk must be quoted: \(line)")
    #expect(line.contains("1 项审批等你"), "owed queue must surface: \(line)")
    #expect(!line.contains("一切安静"), "traffic answered quiet: \(line)")

    // a quiet company gets the quiet sentence, and still its owed queue
    store.events = []
    store.approvals = [ApprovalRequest(productID: store.selectedProductID,
                                       title: "等", reason: "r", status: .pending)]
    let q = store.standupHeadlineText(hours: 24, now: now)
    #expect(q.contains("一切安静") && q.contains("1 项审批等你"),
            "quiet + owed: \(q)")
}

private func temporarySupportDir(_ tag: String) throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("opc-\(tag)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
