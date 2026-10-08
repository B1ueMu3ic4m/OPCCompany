import Foundation
import Testing

@testable import OPCCompanyCore

// v1.22 `task_show` over the real @_cdecl ABI. The serializer tests prove
// the math; this file proves the CHANNEL: the object rides
// opc_bridge_last_error with rc=0, a bad payload refuses, repetition is
// byte-stable, and the unknown-verb refusal stays shut next to the new
// case. Isolation rides the seam; the seed is saved IN-PROCESS before
// create.

// opc_bridge_create() is a process-global singleton, so every caller
// runs serially via OPCBridgeABIDoorTests (.serialized).
extension OPCBridgeABIDoorTests {
    @MainActor
    @Test func bridgeTaskFileOverRealABI() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("opc-task-bridge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        CompanyPersistence.testSupportDirectoryOverride = tmp
        defer { CompanyPersistence.testSupportDirectoryOverride = nil }

        let store = CompanyStore.bootstrap(loadPersisted: false)
        let pid = store.selectedProductID
        let alice = store.agents.first!.id
        var task = CompanyTask(productID: pid, title: "桥上读任务",
                               ownerID: alice, status: .running,
                               successCriteria: "abi smoke")
        store.tasks = [task]
        task = store.tasks[0]
        store.saveSnapshot()

        #expect(opc_bridge_create() == 0)
        defer { opc_bridge_destroy() }
        let verb = strdup("task_show")
        defer { free(verb) }
        let payload = strdup("{\"taskID\":\"\(task.id.uuidString)\"}")
        defer { free(payload) }

        #expect(opc_bridge_command(verb, payload) == 0)
        let raw = String(cString: try #require(opc_bridge_last_error()))
        let d = try #require(
            JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        #expect(d["taskID"] as? String == task.id.uuidString)
        #expect(d["title"] as? String == "桥上读任务")
        #expect(d["owner"] as? String != alice.uuidString,
                "owner arrives as a NAME, never a uuid")
        #expect(d["workItems"] is [[String: Any]])
        #expect(d["artifacts"] is [[String: Any]])
        #expect(d["approvals"] is [[String: Any]])
        #expect(d["messages"] is [[String: Any]])

        // byte-stable repetition: same file, same bytes
        #expect(opc_bridge_command(verb, payload) == 0)
        #expect(String(cString: try #require(opc_bridge_last_error())) == raw)

        // a bad payload refuses loudly
        let junkPayload = strdup("{\"taskID\":\"nope\"}")
        defer { free(junkPayload) }
        #expect(opc_bridge_command(verb, junkPayload) == -1)
        #expect(opc_bridge_command(verb, nil) == -1, "a missing taskID refuses too")

        // an unknown-but-valid uuid refuses honestly
        let unknown = strdup("{\"taskID\":\"\(UUID().uuidString)\"}")
        defer { free(unknown) }
        #expect(opc_bridge_command(verb, unknown) == -1)

        // neighbors still refuse (the hole can't widen next to a new case)
        let junk = strdup("task_showx")
        defer { free(junk) }
        #expect(opc_bridge_command(junk, nil) == -1)

        // the query left the write path clean
        let sv = strdup("save")
        defer { free(sv) }
        #expect(opc_bridge_command(sv, nil) == 0)
    }
}
