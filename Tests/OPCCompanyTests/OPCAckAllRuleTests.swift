import Foundation
import Testing

@testable import OPCCompanyCore

// v1.25 `message_ack_all` at the store rule: the ONE batch-ack rule,
// agent-parameterized. Pins: every pending message addressed to the
// agent flips (and ONLY those); the count is the honest receipt; zero
// pending answers 0 with no event and no save; the selection-bound
// variant is the same rule.

@MainActor
@Test func batchAckRuleFlipsOnlyTheRightOnesAndCountsHonestly() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-ack-all-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    let cto = store.ctoID
    let alice = store.agents.first!.id
    let bob = store.agents.count > 1 ? store.agents[1].id : alice
    for i in 0..<3 {
        store.postAgentMessage(productID: pid, fromAgentID: cto, toAgentID: alice,
                               taskID: nil, kind: .taskDispatched,
                               subject: "派发：待确认 \(i)", body: "batch smoke",
                               persist: false)
    }
    store.postAgentMessage(productID: pid, fromAgentID: cto, toAgentID: bob,
                           taskID: nil, kind: .taskDispatched,
                           subject: "派发：给别人的", body: "not alice's",
                           persist: false)

    let acked = store.acknowledgeAgentMessages(for: alice)
    #expect(acked == 3, "only alice's pending messages flip: \(acked)")
    let alicePending = store.selectedProductRecentAgentMessages
        .filter { $0.toAgentID == alice && $0.status == .pending }.count
    #expect(alicePending == 0)
    let bobStillPending = store.selectedProductRecentAgentMessages
        .filter { $0.toAgentID == bob && $0.status == .pending }.count
    #expect(bobStillPending == 1, "someone else's mail is untouched")

    // the receipt is honest on a clear inbox: 0, and nothing moves
    let snapshotBefore = try Data(contentsOf: CompanyPersistence.stateURL)
    let again = store.acknowledgeAgentMessages(for: alice)
    #expect(again == 0, "zero pending answers 0 — never a fake success")
    #expect(try Data(contentsOf: CompanyPersistence.stateURL) == snapshotBefore,
            "an empty batch writes nothing — no event, no save")
}

@MainActor
@Test func batchAckSelectionVariantSharesTheRule() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-ack-all-sel-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let alice = store.agents.first!.id
    store.postAgentMessage(productID: store.selectedProductID,
                           fromAgentID: store.ctoID, toAgentID: alice,
                           taskID: nil, kind: .taskDispatched,
                           subject: "派发：选择确认", body: "sel smoke",
                           persist: false)
    store.selectedAgentID = alice
    #expect(store.acknowledgeSelectedAgentMessages() == 1,
            "the selection-bound variant drives the same batch rule")
}
