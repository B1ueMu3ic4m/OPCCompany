import Foundation
import Testing

@testable import OPCCompanyCore

// ── Battle 3 ("raise hand → approve") behavior pin. The popover itself
// is view layer; what MUST hold regardless of host is: (a) the office's
// only decision path is the guarded facade — a double-click and a
// CLI-decided-first hand both refuse with the ONE shared wording;
// (b) after a decision the per-agent query goes empty, which is what
// drops the raised hand and closes the list; (c) the shape contract:
// the waitingApproval rig swaps its header for the interactive one, and
// the popover never calls the bare decideApproval.

// File-local: the main suite's loader is fileprivate and 17k lines away;
// reading one file from Sources/ doesn't need the store aggregation.
private func loadCompanySceneSource() throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent("Sources/OPCCompanyCore/CompanyScene.swift"), encoding: .utf8)
}

@MainActor
@Test func officePopoverDecisionPathIsGuardedAndSelfEmptying() throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    let pid = store.selectedProductID

    let first = ApprovalRequest(productID: pid, requesterID: cto.id, title: "删除缓存目录", reason: "r")
    let stale = ApprovalRequest(productID: pid, requesterID: cto.id, title: "已被命令行抢批", reason: "r2")
    store.approvals.append(first)
    store.approvals.append(stale)
    #expect(store.pendingApprovals(forAgent: cto.id).count == 2)

    // (a) first click succeeds; hand drops (b)
    try store.decideApprovalChecked(first.id, approved: true)
    #expect(store.pendingApprovals(forAgent: cto.id).map(\.title) == ["已被命令行抢批"])

    // another surface decided `stale` (CLI/shell path), then the office
    // popover's click must refuse — never a silent no-op
    try store.decideApprovalChecked(stale.id, approved: false)
    #expect(store.pendingApprovals(forAgent: cto.id).isEmpty)
    var refused: ApprovalDecisionError?
    do {
        try store.decideApprovalChecked(stale.id, approved: true)
    } catch let error as ApprovalDecisionError {
        refused = error
    }
    #expect(refused == .alreadyDecided(id: stale.id))
    // one shared sentence, same as bridge/CLI
    #expect(refused?.bridgeReason(idString: stale.id.uuidString)
        == "approval \(stale.id.uuidString) already decided")

    // ghost id (list raced away mid-click) refuses identically
    var ghost: ApprovalDecisionError?
    do { try store.decideApprovalChecked(UUID(), approved: true) }
    catch let error as ApprovalDecisionError { ghost = error }
    #expect(ghost != nil)
}

@MainActor
@Test func officePopoverShapeContract() throws {
    let scene = try loadCompanySceneSource()
    // the waitingApproval rig uses the interactive header, geometry intact
    #expect(scene.contains("agent.status == .waitingApproval"))
    #expect(scene.contains("WaitingApprovalRigHeader(agent: agent, phase: statusPhase)"))
    // same safe-zone in BOTH header branches (measured: exactly the desk's
    // if/else pair) — the desks never jump on a status transition
    let frames = scene.components(separatedBy: "PixelWorkstationLayout.statusSafeZoneHeight").count - 1
    #expect(frames == 2)
    // tap opens the popover; decision goes through the guarded door only
    #expect(scene.contains(".onTapGesture { showingPanel = true }"))
    #expect(scene.contains("OfficeApprovalPopover(agent: agent)"))
    #expect(scene.contains("try store.decideApprovalChecked(id, approved: approved)"))
    #expect(!scene.contains("store.decideApproval("), "the office must never bypass the guarded facade")
    // refusal wording surfaces verbatim from the shared error, not a local copy
    #expect(scene.contains("error.bridgeReason(idString: id.uuidString)"))
}
