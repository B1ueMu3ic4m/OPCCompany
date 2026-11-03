import Foundation
import Testing

@testable import OPCCompanyCore

// v1.30 `decide` write receipt at the serializer: the just-decided
// approval — status, decidedAt, the linked task's new status. Pins: the
// shape after a REAL decision, the task link riding, unknown ids refuse,
// byte-stable repetition.

@MainActor
@Test func decisionReceiptShapeAfterARealDecision() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-decide-receipt-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    var approval = ApprovalRequest(productID: pid, requesterID: store.agents.first!.id,
                                   title: "等批", reason: "r", status: .pending)
    store.approvals = [approval]
    approval = store.approvals[0]
    var task = CompanyTask(productID: pid, title: "链任务", ownerID: store.agents.first!.id,
                           status: .blocked, successCriteria: "s")
    store.tasks = [task]
    task = store.tasks[0]
    store.approvals[0].taskID = task.id

    try store.decideApprovalChecked(approval.id, approved: true)
    let data = try store.decisionReceiptJSON(approvalID: approval.id)
    let d = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(d["approvalID"] as? String == approval.id.uuidString)
    #expect(d["title"] as? String == "等批")
    #expect(d["status"] as? String == "approved")
    #expect(d["decidedAt"] is Int, "the decision carries its timestamp")
    #expect(d["taskID"] as? String == task.id.uuidString)
    #expect(d["taskStatus"] as? String == "running",
            "an approval flips its linked task to running: \(d)")

    // byte-stable repetition (sync body)
    #expect(try store.decisionReceiptJSON(approvalID: approval.id) == data)

    // an unknown id refuses honestly
    #expect(throws: OPCBridgeRefusal.self) {
        try store.decisionReceiptJSON(approvalID: UUID())
    }
}
