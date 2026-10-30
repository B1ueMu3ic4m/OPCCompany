import Foundation
import Testing

@testable import OPCCompanyCore

// v1.26 `checkpoints_list` over the real @_cdecl ABI: the array rides
// opc_bridge_last_error with rc=0, the limit knob rides the payload,
// an empty archive answers [], and the unknown-verb refusal stays shut
// next to the new case. Isolation rides the seam; seeds saved IN-PROCESS.

// opc_bridge_create() is a process-global singleton, so every caller
// runs serially via OPCBridgeABIDoorTests (.serialized).
extension OPCBridgeABIDoorTests {
    @MainActor
    @Test func bridgeCheckpointsLedgerOverRealABI() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("opc-cpl-bridge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        CompanyPersistence.testSupportDirectoryOverride = tmp
        defer { CompanyPersistence.testSupportDirectoryOverride = nil }

        let store = CompanyStore.bootstrap(loadPersisted: false)
        store.createSafetyCheckpoint(reason: "bridge filing")
        store.saveSnapshot()

        #expect(opc_bridge_create() == 0)
        defer { opc_bridge_destroy() }
        let verb = strdup("checkpoints_list")
        defer { free(verb) }

        #expect(opc_bridge_command(verb, nil) == 0)
        let raw = String(cString: try #require(opc_bridge_last_error()))
        let rows = try #require(
            JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]])
        #expect(rows.count == 1)
        #expect((rows[0]["file"] as? String)?.hasPrefix("checkpoint-") == true)
        #expect(rows[0]["bytes"] is Int && rows[0]["modifiedAt"] is Int)

        // byte-stable repetition: same archive, same bytes
        #expect(opc_bridge_command(verb, nil) == 0)
        #expect(String(cString: try #require(opc_bridge_last_error())) == raw)

        // the limit knob rides the payload
        let limit = strdup("{\"limit\":0}")
        defer { free(limit) }
        #expect(opc_bridge_command(verb, limit) == 0)
        let capped = String(cString: try #require(opc_bridge_last_error()))
        #expect(capped == raw, "limit 0 clamps UP to 1 — one filing stays")

        // an empty payload key is not a refusal — default 20
        let empty = strdup("{}")
        defer { free(empty) }
        #expect(opc_bridge_command(verb, empty) == 0)

        // neighbors still refuse (the hole can't widen next to a new case)
        let junk = strdup("checkpoints_listx")
        defer { free(junk) }
        #expect(opc_bridge_command(junk, nil) == -1)

        // the query left the write path clean
        let sv = strdup("save")
        defer { free(sv) }
        #expect(opc_bridge_command(sv, nil) == 0)
    }
}
