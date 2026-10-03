import Foundation
import Testing

@testable import OPCCompanyCore

// The v0.16 alert door + deduper. The office may now CALL the boss, but
// every decision worth testing lives in the core, pinned here: the door
// is a pure read over the pending queue and the stall watch (approvals
// first, oldest-waiting first; approval-parked stalls are NOT double-
// shouted; capped), alert identity is the DOOR's own id, and the
// deduper never touches company state (UserDefaults-backed storage,
// memory suite here) — first sight shouts, repeat stays silent, pruning
// keeps the stored set finite.

@MainActor
private func alertSeeded(now: Date) throws -> (CompanyStore, UserDefaults) {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("opc-alerts-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = tmp
    defer { CompanyPersistence.testSupportDirectoryOverride = nil }

    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    let alice = store.agents.first!.id
    var task = CompanyTask(productID: pid, title: "T", ownerID: alice,
                           status: .running, successCriteria: "s")
    store.tasks = [task]
    task = store.tasks[0]
    store.workQueue = [
        // approval-parked stall — already covered by the pending queue above
        AgentWorkItem(productID: pid, taskID: task.id, agentID: alice,
                      status: .waitingApproval, promptPreview: "p",
                      updatedAt: now.addingTimeInterval(-90 * 60)),
        // a plain stall, no approval involved
        AgentWorkItem(id: UUID(), productID: pid, taskID: task.id, agentID: alice,
                      status: .running, promptPreview: "q",
                      updatedAt: now.addingTimeInterval(-45 * 60)),
    ]
    let defaults = UserDefaults(suiteName: "opc-alerts-test-\(UUID().uuidString)")!
    return (store, defaults)
}

@Test @MainActor func alertDoorQuotesTheDoorsWithoutDoubleShouting() throws {
    let now = Date()
    let (store, _) = try alertSeeded(now: now)

    // one pending approval => one approval alert (the approval-parked
    // stall row is the SAME cause and must not appear twice)
    let approval = ApprovalRequest(productID: store.selectedProductID,
                                   requesterID: store.agents.first!.id,
                                   title: "等批", reason: "r", status: .pending)
    store.approvals = [approval]
    let alerts = store.bossAlerts(now: now)
    #expect(alerts.count == 2, "1 approval + 1 non-approval stall: \(alerts)")
    #expect(alerts[0].kind == .approval && alerts[0].id == approval.id.uuidString)
    #expect(alerts[0].body.contains("等批"))
    #expect(alerts[1].kind == .stall)

    // no pending approvals => the stall row stands alone (no approval
    // alert, no waiting-on-you marker)
    store.approvals = []
    let only = store.bossAlerts(now: now)
    #expect(only.count == 1 && only[0].kind == .stall)
    #expect(!only[0].body.contains("waits on you"))

    // an empty office is quiet — the caller must not page the boss for
    // nothing
    store.workQueue = []
    #expect(store.bossAlerts(now: now).isEmpty)
}

@Test @MainActor func alertDoorCapsTheBanners() throws {
    let now = Date()
    let (store, _) = try alertSeeded(now: now)
    store.workQueue = []
    var approvals: [ApprovalRequest] = []
    for i in 0..<9 {
        approvals.append(ApprovalRequest(productID: store.selectedProductID,
                                         title: "第\(i)件", reason: "r",
                                         status: .pending,
                                         createdAt: now.addingTimeInterval(Double(-i))))
    }
    store.approvals = approvals
    let alerts = store.bossAlerts(now: now, cap: 5)
    #expect(alerts.count == 5, "capped: \(alerts.count)")
    #expect(Set(alerts.map(\.id)).count == 5)
}

@Test @MainActor func deduperShoutsOnceAndPrunesHandledCauses() throws {
    let now = Date()
    let (store, defaults) = try alertSeeded(now: now)
    let approval = ApprovalRequest(productID: store.selectedProductID,
                                   requesterID: store.agents.first!.id,
                                   title: "等批", reason: "r", status: .pending)
    store.approvals = [approval]
    store.workQueue = []
    let deduper = BossAlertDeduper(defaults: defaults)
    let alerts = store.bossAlerts(now: now)

    // first sight: delivered; second sight: silent (the boss was told)
    #expect(deduper.partition(alerts).count == 1)
    #expect(deduper.partition(alerts).isEmpty)

    // a NEW approval is a NEW shout even while an old one is still pending
    let second = ApprovalRequest(productID: store.selectedProductID,
                                 requesterID: store.agents.first!.id,
                                 title: "再批一件", reason: "r", status: .pending)
    store.approvals.append(second)
    let fresh = deduper.partition(store.bossAlerts(now: now))
    #expect(fresh.count == 1 && fresh[0].id == second.id.uuidString)

    // handled causes are pruned: the stored set cannot grow forever
    deduper.prune(keeping: Set(store.bossAlerts(now: now).map(\.id)))
    #expect(deduper.deliveredIds() == Set(store.bossAlerts(now: now).map(\.id)))

    // notifying never moved a single company byte
    #expect(store.approvals.count == 2)
    #expect(store.approvals.allSatisfy { $0.status == .pending })
}
