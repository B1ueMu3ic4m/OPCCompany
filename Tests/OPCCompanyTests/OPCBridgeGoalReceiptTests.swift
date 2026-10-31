import Foundation
import Testing

@testable import OPCCompanyCore

// v1.29 `goal` write receipt over the real @_cdecl ABI: after the save,
// the receipt rides opc_bridge_last_error as a JSON OBJECT; the ids a
// script sees are real task ids. Isolation rides the seam; seed saved
// IN-PROCESS.

// opc_bridge_create() is a process-global singleton, so every caller
// runs serially via OPCBridgeABIDoorTests (.serialized).
extension OPCBridgeABIDoorTests {
    @MainActor
    @Test func bridgeGoalReceiptOverRealABI() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("opc-goal-bridge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        CompanyPersistence.testSupportDirectoryOverride = tmp
        defer { CompanyPersistence.testSupportDirectoryOverride = nil }

        let store = CompanyStore.bootstrap(loadPersisted: false)
        store.saveSnapshot()

        #expect(opc_bridge_create() == 0)
        defer { opc_bridge_destroy() }
        let verb = strdup("goal")
        defer { free(verb) }
        let payload = strdup("{\"text\":\"bridge the receipt\"}")
        defer { free(payload) }

        #expect(opc_bridge_command(verb, payload) == 0)
        let raw = String(cString: try #require(opc_bridge_last_error()))
        let d = try #require(
            JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        #expect(d["goal"] as? String == "bridge the receipt")
        let tasks = try #require(d["tasks"] as? [[String: Any]])
        #expect(tasks.count == 4, "the chain is cto + engineer + reviewer + boss: \(tasks.count)")

        // every id is a REAL task id on the BRIDGE's own store: the
        // receipt ids feed task_show (the round-trip a script performs)
        let taskShow = strdup("task_show")
        defer { free(taskShow) }
        for row in tasks {
            let id = row["id"] as? String ?? ""
            let show = strdup("{\"taskID\":\"\(id)\"}")
            defer { free(show) }
            #expect(opc_bridge_command(taskShow, show) == 0,
                    "receipt id \(id) feeds task_show")
        }

        // byte-stable repetition of the ASK fails honestly (a second goal
        // creates a SECOND chain) — repetition is pinned at the serializer
        let empty = strdup("{\"text\":\"   \"}")
        defer { free(empty) }
        #expect(opc_bridge_command(verb, empty) == -1, "an empty goal still refuses")
        #expect(opc_bridge_command(verb, nil) == -1)

        // neighbors still refuse (the hole can't widen next to a new case)
        let junk = strdup("goalx")
        defer { free(junk) }
        #expect(opc_bridge_command(junk, nil) == -1)

        // the write landed: save still answers clean
        let sv = strdup("save")
        defer { free(sv) }
        #expect(opc_bridge_command(sv, nil) == 0)
    }
}
