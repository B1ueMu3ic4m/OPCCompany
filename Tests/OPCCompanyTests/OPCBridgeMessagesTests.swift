import Foundation
import Testing

@testable import OPCCompanyCore

// v1.21 `messages_list` over the real @_cdecl ABI. The serializer tests
// prove the math; this file proves the CHANNEL: the array rides
// opc_bridge_last_error with rc=0, resolved names and the drill filter
// hold across the ABI, repetition is byte-stable, and the unknown-verb
// refusal stays shut next to the new case. Isolation rides the seam; the
// seed is saved IN-PROCESS before create.

// opc_bridge_create() is a process-global singleton, so every caller
// runs serially via OPCBridgeABIDoorTests (.serialized).
extension OPCBridgeABIDoorTests {
    @MainActor
    @Test func bridgeMessagesBusOverRealABI() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("opc-bus-bridge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        CompanyPersistence.testSupportDirectoryOverride = tmp
        defer { CompanyPersistence.testSupportDirectoryOverride = nil }

        let store = CompanyStore.bootstrap(loadPersisted: false)
        let cto = store.ctoID
        let alice = store.agents.first!.id
        store.postAgentMessage(productID: store.selectedProductID,
                               fromAgentID: cto, toAgentID: alice,
                               taskID: nil, kind: .taskDispatched,
                               subject: "派发：桥上走一趟",
                               body: "abi smoke", persist: false)
        store.saveSnapshot()

        #expect(opc_bridge_create() == 0)
        defer { opc_bridge_destroy() }
        let verb = strdup("messages_list")
        defer { free(verb) }

        #expect(opc_bridge_command(verb, nil) == 0)
        let raw = String(cString: try #require(opc_bridge_last_error()))
        let rows = try #require(
            JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]])
        #expect(rows.count == 1)
        #expect(rows[0]["subject"] as? String == "派发：桥上走一趟")
        #expect(rows[0]["from"] as? String
            == store.agents.first(where: { $0.id == cto })!.displayName,
            "the bridge serves resolved names too")

        // byte-stable repetition: same bus, same bytes
        #expect(opc_bridge_command(verb, nil) == 0)
        #expect(String(cString: try #require(opc_bridge_last_error())) == raw)

        // a payload is ignored, not a refusal — the door takes none
        let p = strdup("{}")
        defer { free(p) }
        #expect(opc_bridge_command(verb, p) == 0)
        #expect(String(cString: try #require(opc_bridge_last_error())) == raw)

        // neighbors still refuse (the hole can't widen next to a new case)
        let junk = strdup("messages_listx")
        defer { free(junk) }
        #expect(opc_bridge_command(junk, nil) == -1)

        // the query left the write path clean
        let sv = strdup("save")
        defer { free(sv) }
        #expect(opc_bridge_command(sv, nil) == 0)
    }
}
