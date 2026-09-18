import Foundation
import Testing

@testable import OPCCompanyCore

// ── The office popover's data door: pendingApprovals(forAgent:) is the
// ONLY reason a raised pixel hand can show something clickable, and the
// decision path stays exactly one method deep (decideApprovalChecked).
// These four groups pin the query's blast radius: requester mapping,
// product isolation, status filter, and the "no such agent" edge.
@MainActor
@Test func officeApprovalQueryMapsRequesterProductAndStatus() throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    let pid = store.selectedProductID

    // group 1+3: only THIS requester, only PENDING, never the others'
    store.approvals.append(ApprovalRequest(productID: pid, requesterID: cto.id, title: "我的举手", reason: "r1"))
    store.approvals.append(ApprovalRequest(productID: pid, requesterID: cto.id, title: "我已被批", reason: "r2", status: .approved, decidedAt: Date()))
    let other = CompanyAgent(
        displayName: "别人",
        title: "代码工程师",
        role: .codeEngineer,
        backend: AgentBackend(type: .subscriptionCLI, command: "claude", model: "sonnet"),
        ethnicity: .chinese,
        gender: .man,
        clothing: .smartCasual,
        status: .idle,
        permissions: [.readFiles],
        seat: OfficeSeat(x: 0.5, y: 0.5, room: "employee-hall")
    )
    store.approvals.append(ApprovalRequest(productID: pid, requesterID: other.id, title: "别人的举手", reason: "r3"))

    #expect(store.pendingApprovals(forAgent: cto.id).map(\.title) == ["我的举手"])

    // group 2: cross-product isolation. addProductWorkspace() AUTO-SELECTS
    // the new product (CompanyStore+Workspace:858) — the query follows the
    // current selection in both directions, never leaking the other
    // product's pending items (and the ghost-agent case below pins the
    // "no such agent" edge).
    store.addProductWorkspace()
    let second = store.products[1].id
    store.approvals.append(ApprovalRequest(productID: second, requesterID: cto.id, title: "隔壁项目的举手", reason: "r4"))
    #expect(store.pendingApprovals(forAgent: cto.id).map(\.title) == ["隔壁项目的举手"])

    store.selectProduct(pid)
    #expect(store.pendingApprovals(forAgent: cto.id).map(\.title) == ["我的举手"])

    store.selectProduct(second)
    #expect(store.pendingApprovals(forAgent: cto.id).map(\.title) == ["隔壁项目的举手"])

    // group 4: unknown agent → empty; and the query never mutates anything
    #expect(store.pendingApprovals(forAgent: UUID()).isEmpty)
    let before = store.approvals.count
    _ = store.pendingApprovals(forAgent: cto.id)
    #expect(store.approvals.count == before)
}
