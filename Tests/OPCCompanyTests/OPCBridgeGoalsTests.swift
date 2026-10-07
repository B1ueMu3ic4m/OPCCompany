import Foundation
import Testing

@testable import OPCCompanyCore

// v1.19 `goals_list` over the real @_cdecl ABI. The serializer tests prove
// the math; this file proves the CHANNEL: the array rides
// opc_bridge_last_error with rc=0, a started goal arrives as one row,
// repetition is byte-stable, and the unknown-verb refusal stays shut next
// to the new case. Isolation rides the seam (a support-dir setenv would be
// dead theater after the first-touch bake); the seed is saved IN-PROCESS
// before create.

// opc_bridge_create() is a process-global singleton, so every caller
// runs serially via OPCBridgeABIDoorTests (.serialized).
extension OPCBridgeABIDoorTests {
    @MainActor
    @Test func bridgeGoalsLedgerOverRealABI() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("opc-goals-bridge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        CompanyPersistence.testSupportDirectoryOverride = tmp
        defer { CompanyPersistence.testSupportDirectoryOverride = nil }

        let store = CompanyStore.bootstrap(loadPersisted: false)
        #expect(try (JSONSerialization.jsonObject(
            with: try store.goalsListJSON()) as? [[String: Any]] ?? []).isEmpty)
        #expect(store.startCTOSupervisorGoal(goal: "bridge the goals door") != nil)

        #expect(opc_bridge_create() == 0)
        defer { opc_bridge_destroy() }
        let verb = strdup("goals_list")
        defer { free(verb) }

        #expect(opc_bridge_command(verb, nil) == 0)
        let raw = String(cString: try #require(opc_bridge_last_error()))
        let rows = try #require(
            JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]])
        #expect(rows.count == 1, "the bridge sees the goal started IN-PROCESS: \(rows)")
        #expect(rows[0]["goal"] as? String == "bridge the goals door")
        #expect(rows[0]["steps"] is [[String: Any]])
        #expect(rows[0]["counts"] is [String: Any])

        // byte-stable repetition: same ledger, same bytes
        #expect(opc_bridge_command(verb, nil) == 0)
        #expect(String(cString: try #require(opc_bridge_last_error())) == raw)

        // a payload is ignored, not a refusal — the door takes none
        let p = strdup("{}")
        defer { free(p) }
        #expect(opc_bridge_command(verb, p) == 0)
        #expect(String(cString: try #require(opc_bridge_last_error())) == raw)

        // neighbors still refuse (the hole can't widen next to a new case)
        let junk = strdup("goals_listx")
        defer { free(junk) }
        #expect(opc_bridge_command(junk, nil) == -1)

        // the query left the write path clean
        let sv = strdup("save")
        defer { free(sv) }
        #expect(opc_bridge_command(sv, nil) == 0)
    }
}
