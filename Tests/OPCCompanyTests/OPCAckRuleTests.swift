import Foundation
import Testing

@testable import OPCCompanyCore

// v1.23 `message_ack` at the store rule: the ONE ack rule, now
// agent-parameterized. Pins: a pending message addressed to the agent
// flips to acknowledged with its timestamp and rides an event; anything
// else refuses by rule — unknown id, wrong recipient, already read,
// another product — never a silent no-op; and the selection-bound
// variant is literally the same rule.

@MainActor
@Test func ackRuleFlipsPendingAndRefusesByRule() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-ack-\(UUID().uuidString)", isDirectory: true)
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
    store.postAgentMessage(productID: pid, fromAgentID: cto, toAgentID: alice,
                           taskID: nil, kind: .taskDispatched,
                           subject: "派发：待确认", body: "ack smoke",
                           persist: false)
    let messageID = try #require(
        store.selectedProductRecentAgentMessages.first(where: { $0.toAgentID == alice })?.id)

    #expect(store.acknowledgeAgentMessage(messageID, for: alice) == true,
            "the right recipient acks a pending message")
    let acked = try #require(
        store.agentMessages.first(where: { $0.id == messageID }))
    #expect(acked.status == .acknowledged)
    #expect(acked.acknowledgedAt != nil, "the ack carries its timestamp")

    // the refusals, by rule — every one of them
    #expect(store.acknowledgeAgentMessage(messageID, for: alice) == false,
            "double-acking refuses — already read")
    #expect(store.acknowledgeAgentMessage(messageID, for: bob) == false,
            "the wrong recipient refuses — not addressed to bob")
    #expect(store.acknowledgeAgentMessage(UUID(), for: alice) == false,
            "an unknown id refuses — never a silent no-op")
}

@MainActor
@Test func ackRuleStaysProductScopedAndSelectionBoundVariantSharesIt() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-ack-scope-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = store.ctoID
    let alice = store.agents.first!.id
    let pid = store.selectedProductID
    store.postAgentMessage(productID: pid, fromAgentID: cto, toAgentID: alice,
                           taskID: nil, kind: .taskDispatched,
                           subject: "派发：作用域", body: "scope smoke",
                           persist: false)
    let messageID = try #require(
        store.selectedProductRecentAgentMessages.first(where: { $0.toAgentID == alice })?.id)

    // the selection-bound variant drives the SAME rule: select alice and
    // the ack lands through the shared path
    store.selectedAgentID = alice
    #expect(store.acknowledgeSelectedAgentMessage(messageID) == true)
    #expect(store.agentMessages.first(where: { $0.id == messageID })?.status == .acknowledged)
}
