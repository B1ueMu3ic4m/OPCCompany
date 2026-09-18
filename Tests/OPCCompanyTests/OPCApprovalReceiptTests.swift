import Foundation
import Testing

@testable import OPCCompanyCore

// v0.6.0 "every hand leaves a receipt" — the single shared attribution
// lookup the command center, `opc history` and the bridge all read from.
// Three shapes, no fabrication: an owner resolves to the employee, a
// missing requester says unassigned, a stale id says unknown employee.
@MainActor
@Test func approvalReceiptAttributionNeverFabricatesAnOwner() throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    let pid = store.selectedProductID

    // owned: resolves through the roster like every other employee-facing
    // view — displayName, not id, not role.
    let owned = ApprovalRequest(productID: pid, requesterID: cto.id, title: "t1", reason: "r")
    #expect(store.requesterDisplayName(for: owned) == cto.displayName)

    // unowned: the honest empties — never a made-up owner.
    let unassigned = ApprovalRequest(productID: pid, requesterID: nil, title: "t2", reason: "r")
    #expect(store.requesterDisplayName(for: unassigned) == "未分配".L())
    let stale = ApprovalRequest(productID: pid, requesterID: UUID(), title: "t3", reason: "r")
    #expect(store.requesterDisplayName(for: stale) == "未知员工".L())
}

@Test func approvalReceiptKeyRidesTheL10nTable() throws {
    // XCTest forces Chinese, so .L() is identity for table'd prefixes; pin
    // the EN side through the explicit-language door so the l10n table —
    // not a literal fallback — is what English users actually see.
    #expect("来自 ".zh(.english) == "From ")
}

// File-local loader: the main suite's is fileprivate and far away; reading
// one source file needs no aggregation.
private func loadCommandCenterSource() throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent("Sources/OPCCompanyCore/CommandCenterView.swift"), encoding: .utf8)
}

// Shape pin: BOTH row types (pending + decided) render the attribution line
// through the shared store lookup — a drift back to per-row name logic
// reopens the exact inconsistency v0.6.0 closed.
@Test func commandCenterRowsShareOneAttributionDoor() throws {
    let src = try loadCommandCenterSource()
    let uses = src.components(separatedBy: "requesterDisplayName(for:").count - 1
    #expect(uses >= 2)
}
