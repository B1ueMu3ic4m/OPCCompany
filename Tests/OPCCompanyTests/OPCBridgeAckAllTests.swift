import Foundation
import Testing

@testable import OPCCompanyCore

// v1.25 `message_ack_all` over the real @_cdecl ABI: the batch acks
// through the bridge, the snapshot moves, the {"acked":N} receipt rides
// the smuggle channel, and a clear inbox answers 0 without writing.
// Isolation rides the seam; the seed is saved IN-PROCESS before create.

// opc_bridge_create() is a process-global singleton, so every caller
// runs serially via OPCBridgeABIDoorTests (.serialized).
extension OPCBridgeABIDoorTests {
    @MainActor
    @Test func bridgeBatchAckOverRealABI() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("opc-ack-all-bridge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        CompanyPersistence.testSupportDirectoryOverride = tmp
        defer { CompanyPersistence.testSupportDirectoryOverride = nil }

        let store = CompanyStore.bootstrap(loadPersisted: false)
        let alice = store.agents.first!.id
        store.postAgentMessage(productID: store.selectedProductID,
                               fromAgentID: store.ctoID, toAgentID: alice,
                               taskID: nil, kind: .taskDispatched,
                               subject: "派发：桥上批量", body: "abi smoke",
                               persist: false)
        store.saveSnapshot()
        let before = try Data(contentsOf: tmp.appendingPathComponent("company-state.json"))

        #expect(opc_bridge_create() == 0)
        defer { opc_bridge_destroy() }
        let verb = strdup("message_ack_all")
        defer { free(verb) }
        let payload = strdup("{\"agentID\":\"\(alice.uuidString)\"}")
        defer { free(payload) }

        #expect(opc_bridge_command(verb, payload) == 0)
        let raw = String(cString: try #require(opc_bridge_last_error()))
        let receipt = try #require(
            JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        #expect(receipt["acked"] as? Int == 1, "the receipt counts the batch")
        let after = try Data(contentsOf: tmp.appendingPathComponent("company-state.json"))
        #expect(after != before, "a batch ack is a WRITE — the snapshot moves")

        // a clear inbox answers 0 honestly, and writes nothing
        #expect(opc_bridge_command(verb, payload) == 0)
        let again = String(cString: try #require(opc_bridge_last_error()))
        #expect(again == "{\"acked\":0}", "sortedKeys bytes: \(again)")
        let afterAgain = try Data(contentsOf: tmp.appendingPathComponent("company-state.json"))
        #expect(afterAgain == after, "an empty batch writes nothing")

        // bad payloads refuse
        #expect(opc_bridge_command(verb, nil) == -1)
        let junkPayload = strdup("{}")
        defer { free(junkPayload) }
        #expect(opc_bridge_command(verb, junkPayload) == -1)

        // neighbors still refuse (the hole can't widen next to a new case)
        let junk = strdup("message_ack_allx")
        defer { free(junk) }
        #expect(opc_bridge_command(junk, nil) == -1)
    }
}
