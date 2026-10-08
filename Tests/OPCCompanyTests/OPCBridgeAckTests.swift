import Foundation
import Testing

@testable import OPCCompanyCore

// v1.23 `message_ack` over the real @_cdecl ABI. The store-rule tests
// prove the math; this file proves the CHANNEL: a pending message acks
// through the bridge, the snapshot moves (a WRITE), double acks refuse,
// and the unknown-verb refusal stays shut next to the new case.
// Isolation rides the seam; the seed is saved IN-PROCESS before create.

// opc_bridge_create() is a process-global singleton, so every caller
// runs serially via OPCBridgeABIDoorTests (.serialized).
extension OPCBridgeABIDoorTests {
    @MainActor
    @Test func bridgeMessageAckOverRealABI() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("opc-ack-bridge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        CompanyPersistence.testSupportDirectoryOverride = tmp
        defer { CompanyPersistence.testSupportDirectoryOverride = nil }

        let store = CompanyStore.bootstrap(loadPersisted: false)
        let alice = store.agents.first!.id
        store.postAgentMessage(productID: store.selectedProductID,
                               fromAgentID: store.ctoID, toAgentID: alice,
                               taskID: nil, kind: .taskDispatched,
                               subject: "派发：桥上确认", body: "abi smoke",
                               persist: false)
        store.saveSnapshot()
        let messageID = try #require(
            store.selectedProductRecentAgentMessages.first(where: { $0.toAgentID == alice })?.id)
        let before = try Data(contentsOf: tmp.appendingPathComponent("company-state.json"))

        #expect(opc_bridge_create() == 0)
        defer { opc_bridge_destroy() }
        let verb = strdup("message_ack")
        defer { free(verb) }
        let payload = strdup(
            "{\"messageID\":\"\(messageID.uuidString)\",\"agentID\":\"\(alice.uuidString)\"}")
        defer { free(payload) }

        #expect(opc_bridge_command(verb, payload) == 0,
                "the right recipient acks through the bridge")
        let after = try Data(contentsOf: tmp.appendingPathComponent("company-state.json"))
        #expect(after != before, "an ack is a WRITE — the snapshot moves")

        // double ack refuses loudly, rc=-1 with its reason
        #expect(opc_bridge_command(verb, payload) == -1)
        #expect(String(cString: try #require(opc_bridge_last_error()))
            .contains("must be PENDING"))

        // a wrong recipient refuses by rule
        let wrongAgent = strdup(
            "{\"messageID\":\"\(messageID.uuidString)\",\"agentID\":\"\(UUID().uuidString)\"}")
        defer { free(wrongAgent) }
        #expect(opc_bridge_command(verb, wrongAgent) == -1)

        // bad payloads refuse
        #expect(opc_bridge_command(verb, nil) == -1)
        let junkPayload = strdup("{}")
        defer { free(junkPayload) }
        #expect(opc_bridge_command(verb, junkPayload) == -1)

        // neighbors still refuse (the hole can't widen next to a new case)
        let junk = strdup("message_ackx")
        defer { free(junk) }
        #expect(opc_bridge_command(junk, nil) == -1)
    }
}
