import Foundation
import Testing

@testable import OPCCompanyCore

// v1.30 `decide` write receipt over the real @_cdecl ABI: the receipt
// rides opc_bridge_last_error as a JSON OBJECT after the save; a stale
// decision still refuses; the unknown-verb refusal stays shut. Isolation
// rides the seam; seed saved IN-PROCESS.

// opc_bridge_create() is a process-global singleton, so every caller
// runs serially via OPCBridgeABIDoorTests (.serialized).
extension OPCBridgeABIDoorTests {
    @MainActor
    @Test func bridgeDecideReceiptOverRealABI() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("opc-decide-bridge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        CompanyPersistence.testSupportDirectoryOverride = tmp
        defer { CompanyPersistence.testSupportDirectoryOverride = nil }

        let store = CompanyStore.bootstrap(loadPersisted: false)
        let approval = ApprovalRequest(productID: store.selectedProductID,
                                       requesterID: store.agents.first!.id,
                                       title: "桥上待批", reason: "abi smoke",
                                       status: .pending)
        store.approvals = [approval]
        store.saveSnapshot()

        #expect(opc_bridge_create() == 0)
        defer { opc_bridge_destroy() }
        let verb = strdup("decide")
        defer { free(verb) }
        let payload = strdup(
            "{\"approvalID\":\"\(approval.id.uuidString)\",\"approved\":true}")
        defer { free(payload) }

        #expect(opc_bridge_command(verb, payload) == 0)
        let raw = String(cString: try #require(opc_bridge_last_error()))
        let d = try #require(
            JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        #expect(d["approvalID"] as? String == approval.id.uuidString)
        #expect(d["status"] as? String == "approved")
        #expect(d["decidedAt"] is Int)

        // a stale decision refuses (already decided) — the receipt never
        // pretends a no-op was a success
        #expect(opc_bridge_command(verb, payload) == -1)
        #expect(String(cString: try #require(opc_bridge_last_error()))
            .contains("already"))

        // bad payloads refuse
        #expect(opc_bridge_command(verb, nil) == -1)

        // neighbors still refuse (the hole can't widen next to a new case)
        let junk = strdup("decidex")
        defer { free(junk) }
        #expect(opc_bridge_command(junk, nil) == -1)

        // the write landed: save still answers clean
        let sv = strdup("save")
        defer { free(sv) }
        #expect(opc_bridge_command(sv, nil) == 0)
    }
}
