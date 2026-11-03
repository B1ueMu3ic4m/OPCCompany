import Foundation
import Testing

@testable import OPCCompanyCore

// v1.31 `checkpoint` write receipt over the real @_cdecl ABI: the receipt
// rides opc_bridge_last_error as a JSON OBJECT after the save; an empty
// reason still refuses. Isolation rides the seam; seed saved IN-PROCESS.

// opc_bridge_create() is a process-global singleton, so every caller
// runs serially via OPCBridgeABIDoorTests (.serialized).
extension OPCBridgeABIDoorTests {
    @MainActor
    @Test func bridgeCheckpointReceiptOverRealABI() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("opc-cp-bridge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        CompanyPersistence.testSupportDirectoryOverride = tmp
        defer { CompanyPersistence.testSupportDirectoryOverride = nil }

        let store = CompanyStore.bootstrap(loadPersisted: false)
        store.saveSnapshot()

        #expect(opc_bridge_create() == 0)
        defer { opc_bridge_destroy() }
        let verb = strdup("checkpoint")
        defer { free(verb) }
        let payload = strdup("{\"reason\":\"abi receipt smoke\"}")
        defer { free(payload) }

        #expect(opc_bridge_command(verb, payload) == 0)
        let raw = String(cString: try #require(opc_bridge_last_error()))
        let d = try #require(
            JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        #expect((d["file"] as? String)?.hasPrefix("checkpoint-") == true)
        #expect(d["bytes"] is Int)
        #expect(d["reason"] as? String == "abi receipt smoke")

        // an empty reason still refuses
        let empty = strdup("{\"reason\":\"   \"}")
        defer { free(empty) }
        #expect(opc_bridge_command(verb, empty) == -1)

        // neighbors still refuse (the hole can't widen next to a new case)
        let junk = strdup("checkpointx")
        defer { free(junk) }
        #expect(opc_bridge_command(junk, nil) == -1)

        // the write landed: save still answers clean
        let sv = strdup("save")
        defer { free(sv) }
        #expect(opc_bridge_command(sv, nil) == 0)
    }
}
