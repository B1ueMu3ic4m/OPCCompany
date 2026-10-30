import Foundation
import Testing

@testable import OPCCompanyCore

// v1.27 `products_list` over the real @_cdecl ABI: the array rides
// opc_bridge_last_error with rc=0, the selected flag marks exactly the
// bridge store's own selection, and the unknown-verb refusal stays shut
// next to the new case. Isolation rides the seam; seed saved IN-PROCESS.

// opc_bridge_create() is a process-global singleton, so every caller
// runs serially via OPCBridgeABIDoorTests (.serialized).
extension OPCBridgeABIDoorTests {
    @MainActor
    @Test func bridgeProductsRosterOverRealABI() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("opc-products-bridge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        CompanyPersistence.testSupportDirectoryOverride = tmp
        defer { CompanyPersistence.testSupportDirectoryOverride = nil }

        let store = CompanyStore.bootstrap(loadPersisted: false)
        store.saveSnapshot()

        #expect(opc_bridge_create() == 0)
        defer { opc_bridge_destroy() }
        let verb = strdup("products_list")
        defer { free(verb) }

        #expect(opc_bridge_command(verb, nil) == 0)
        let raw = String(cString: try #require(opc_bridge_last_error()))
        let rows = try #require(
            JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]])
        #expect(rows.count == store.products.count)
        let selected = rows.filter { $0["selected"] as? Bool == true }
        #expect(selected.count == 1)
        #expect(selected[0]["id"] as? String == store.selectedProductID.uuidString)

        // byte-stable repetition: same roster, same bytes
        #expect(opc_bridge_command(verb, nil) == 0)
        #expect(String(cString: try #require(opc_bridge_last_error())) == raw)

        // a payload is ignored, not a refusal — the door takes none
        let p = strdup("{}")
        defer { free(p) }
        #expect(opc_bridge_command(verb, p) == 0)
        #expect(String(cString: try #require(opc_bridge_last_error())) == raw)

        // neighbors still refuse (the hole can't widen next to a new case)
        let junk = strdup("products_listx")
        defer { free(junk) }
        #expect(opc_bridge_command(junk, nil) == -1)

        // the query left the write path clean
        let sv = strdup("save")
        defer { free(sv) }
        #expect(opc_bridge_command(sv, nil) == 0)
    }
}
