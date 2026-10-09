import Foundation
import Testing

@testable import OPCCompanyCore

// v1.24 `search` over the real @_cdecl ABI. The serializer tests prove
// the math; this file proves the CHANNEL: the array rides
// opc_bridge_last_error with rc=0, the payload carries the query and the
// limit knob, an empty query refuses, and the unknown-verb refusal stays
// shut next to the new case. Isolation rides the seam; the seed is saved
// IN-PROCESS before create.

// opc_bridge_create() is a process-global singleton, so every caller
// runs serially via OPCBridgeABIDoorTests (.serialized).
extension OPCBridgeABIDoorTests {
    @MainActor
    @Test func bridgeSearchOverRealABI() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("opc-search-bridge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        CompanyPersistence.testSupportDirectoryOverride = tmp
        defer { CompanyPersistence.testSupportDirectoryOverride = nil }

        let store = CompanyStore.bootstrap(loadPersisted: false)
        let pid = store.selectedProductID
        let alice = store.agents.first!.id
        store.tasks = [
            CompanyTask(productID: pid, title: "桥上搜索目标", ownerID: alice,
                        status: .running, successCriteria: "abi smoke"),
        ]
        store.saveSnapshot()

        #expect(opc_bridge_create() == 0)
        defer { opc_bridge_destroy() }
        let verb = strdup("search")
        defer { free(verb) }
        let payload = strdup("{\"query\":\"搜索目标\"}")
        defer { free(payload) }

        #expect(opc_bridge_command(verb, payload) == 0)
        let raw = String(cString: try #require(opc_bridge_last_error()))
        let rows = try #require(
            JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]])
        #expect(rows.count == 1)
        #expect(rows[0]["kind"] as? String == "task")
        #expect(rows[0]["title"] as? String == "桥上搜索目标")

        // byte-stable repetition: same query, same bytes
        #expect(opc_bridge_command(verb, payload) == 0)
        #expect(String(cString: try #require(opc_bridge_last_error())) == raw)

        // the limit knob rides the payload
        let limitPayload = strdup("{\"query\":\"搜索目标\",\"limit\":0}")
        defer { free(limitPayload) }
        #expect(opc_bridge_command(verb, limitPayload) == 0)
        let cappedRaw = String(cString: try #require(opc_bridge_last_error()))
        let capped = try #require(
            JSONSerialization.jsonObject(with: Data(cappedRaw.utf8)) as? [[String: Any]])
        #expect(capped.count == 1, "limit 0 clamps UP to 1 — the knob never fabricates rows")

        // an empty query refuses loudly
        let empty = strdup("{\"query\":\"   \"}")
        defer { free(empty) }
        #expect(opc_bridge_command(verb, empty) == -1)

        // a missing query refuses
        #expect(opc_bridge_command(verb, nil) == -1)

        // zero hits answer [] honestly
        let miss = strdup("{\"query\":\"nothing-matches-this\"}")
        defer { free(miss) }
        #expect(opc_bridge_command(verb, miss) == 0)
        #expect(String(cString: try #require(opc_bridge_last_error())) == "[]")

        // neighbors still refuse (the hole can't widen next to a new case)
        let junk = strdup("searchx")
        defer { free(junk) }
        #expect(opc_bridge_command(junk, nil) == -1)

        // the query left the write path clean
        let sv = strdup("save")
        defer { free(sv) }
        #expect(opc_bridge_command(sv, nil) == 0)
    }
}
