import Foundation
import Testing

@testable import OPCCompanyCore

// v1.20 `risks_list` over the real @_cdecl ABI. The serializer tests prove
// the math; this file proves the CHANNEL: the array rides
// opc_bridge_last_error with rc=0, the boss-view filter holds across the
// ABI, repetition is byte-stable, and the unknown-verb refusal stays shut
// next to the new case. Isolation rides the seam; the seed is saved
// IN-PROCESS before create.

// opc_bridge_create() is a process-global singleton, so every caller
// runs serially via OPCBridgeABIDoorTests (.serialized).
extension OPCBridgeABIDoorTests {
    @MainActor
    @Test func bridgeRisksLedgerOverRealABI() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("opc-risks-bridge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        CompanyPersistence.testSupportDirectoryOverride = tmp
        defer { CompanyPersistence.testSupportDirectoryOverride = nil }

        let store = CompanyStore.bootstrap(loadPersisted: false)
        let now = Date()
        let alice = store.agents.first!.id
        store.events = [
            CompanyEvent(productID: store.selectedProductID, kind: .risk,
                         title: "编译失败：桥层", detail: "abi smoke",
                         agentID: alice,
                         createdAt: now.addingTimeInterval(-600)),
            CompanyEvent(productID: store.selectedProductID, kind: .risk,
                         title: "命令行作业档案写入失败", detail: "whitelisted noise",
                         agentID: alice,
                         createdAt: now.addingTimeInterval(-300)),
        ]
        store.saveSnapshot()

        #expect(opc_bridge_create() == 0)
        defer { opc_bridge_destroy() }
        let verb = strdup("risks_list")
        defer { free(verb) }

        #expect(opc_bridge_command(verb, nil) == 0)
        let raw = String(cString: try #require(opc_bridge_last_error()))
        let rows = try #require(
            JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]])
        #expect(rows.count == 1, "the whitelisted backend noise never crosses the boss door: \(rows.map { $0["title"] })")
        #expect(rows[0]["title"] as? String == "编译失败：桥层")
        #expect(rows[0]["agentID"] as? String == alice.uuidString)

        // byte-stable repetition: same ledger, same bytes
        #expect(opc_bridge_command(verb, nil) == 0)
        #expect(String(cString: try #require(opc_bridge_last_error())) == raw)

        // a payload is ignored, not a refusal — the door takes none
        let p = strdup("{}")
        defer { free(p) }
        #expect(opc_bridge_command(verb, p) == 0)
        #expect(String(cString: try #require(opc_bridge_last_error())) == raw)

        // neighbors still refuse (the hole can't widen next to a new case)
        let junk = strdup("risks_listx")
        defer { free(junk) }
        #expect(opc_bridge_command(junk, nil) == -1)

        // the query left the write path clean
        let sv = strdup("save")
        defer { free(sv) }
        #expect(opc_bridge_command(sv, nil) == 0)
    }
}
