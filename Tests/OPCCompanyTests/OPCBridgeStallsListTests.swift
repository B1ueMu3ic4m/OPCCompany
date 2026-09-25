import Foundation
import Testing

@testable import OPCCompanyCore

// v1.8 `stalls_list` over the real @_cdecl ABI. The CLI-side door tests
// prove the math; this file proves the CHANNEL: row shape, byte-stable
// list order (order IS the contract for list verbs — unlike the v1.6
// object), the payload knob, and the unknown-verb refusal staying shut
// next to the new case. NO fresh-empty asserts: the runner's support dir
// is process-shared (see OPCBridgeStandupWindowTests) — every seed here
// is saved IN-PROCESS before create, so the door sees exactly this list.

private func rowsFrom(_ payload: String) throws -> [[String: Any]] {
    let parsed = try JSONSerialization.jsonObject(with: Data(payload.utf8))
    return parsed as? [[String: Any]] ?? []
}

@MainActor
private func seedStalls(now: Date) throws -> (CompanyStore, UUID) {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    let alice = store.agents.first!.id
    var task = CompanyTask(productID: pid, title: "T", ownerID: alice,
                           status: .running, successCriteria: "s")
    store.tasks = [task]
    task = store.tasks[0]
    let ghost = UUID()   // not in the roster -> unattributed shape
    store.workQueue = [
        AgentWorkItem(productID: pid, taskID: task.id, agentID: alice,
                      status: .waitingApproval, promptPreview: "p",
                      updatedAt: now.addingTimeInterval(-90 * 60)),
        AgentWorkItem(productID: pid, taskID: task.id, agentID: ghost,
                      status: .running, promptPreview: "q",
                      updatedAt: now.addingTimeInterval(-45 * 60)),
        AgentWorkItem(productID: pid, taskID: task.id, agentID: alice,
                      status: .waitingReview, promptPreview: "r",
                      updatedAt: now.addingTimeInterval(-10 * 60)),
    ]
    store.saveSnapshot()
    return (store, alice)
}

@MainActor
@Test func bridgeStallsContractOverRealABI() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("opc-stall-bridge-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    setenv("OPC_COMPANY_SUPPORT_DIR", tmp.path, 1)
    defer { unsetenv("OPC_COMPANY_SUPPORT_DIR") }

    // dwell ages ride the REAL clock: the door subtracts at read time
    let now = Date()
    let (store, alice) = try seedStalls(now: now)
    _ = store  // seeding is the point; alice names the attributed row

    #expect(opc_bridge_create() == 0)
    defer { opc_bridge_destroy() }
    let verb = strdup("stalls_list")
    defer { free(verb) }

    #expect(opc_bridge_command(verb, nil) == 0)
    let raw = String(cString: try #require(opc_bridge_last_error()))
    let rows = try rowsFrom(raw)
    #expect(rows.count == 2, "90m + 45m stall, the 10m item never: \(rows)")
    let first = rows[0]
    #expect(first["agentID"] as? String == alice.uuidString)
    #expect(first["status"] as? String == "waitingApproval")
    #expect(first["waitingOnYou"] as? Bool == true)
    #expect(first["dwellMinutes"] as? Int == 90)
    #expect(rows[0]["itemID"] is String && rows[1]["itemID"] is String,
            "every row carries its item id")
    // unattributed ghost row present and LAST, WITHOUT an agentID key
    let last = rows[1]
    #expect(last["agentID"] == nil, "the ghost keeps no id: \(last)")
    #expect(last["waitingOnYou"] as? Bool == false, "a running stall is not on you")
    // byte-stable repetition: for a LIST verb order IS the contract
    #expect(opc_bridge_command(verb, nil) == 0)
    #expect(String(cString: try #require(opc_bridge_last_error())) == raw,
            "same store, same list, same bytes")

    // over_minutes arrives through the payload and the knob works both
    // ways: at >15 the 10-minute item is still out (two rows stay), at
    // >80 only the approval jam survives (one row).
    let p = strdup("{\"over_minutes\":15}")
    defer { free(p) }
    #expect(opc_bridge_command(verb, p) == 0)
    let same = try rowsFrom(String(cString: try #require(opc_bridge_last_error())))
    #expect(same.count == 2, "10 min !> 15 — knob cannot manufacture rows: \(same)")
    let q = strdup("{\"over_minutes\":80}")
    defer { free(q) }
    #expect(opc_bridge_command(verb, q) == 0)
    let strict = try rowsFrom(String(cString: try #require(opc_bridge_last_error())))
    #expect(strict.count == 1 && strict[0]["waitingOnYou"] as? Bool == true,
            "80-minute ask keeps only the approval jam: \(strict)")

    // neighbors still refuse (the hole can't widen next to a new case)
    let junk = strdup("stalls_listx")
    defer { free(junk) }
    #expect(opc_bridge_command(junk, nil) == -1)

    // the query left the write path clean
    let sv = strdup("save")
    defer { free(sv) }
    #expect(opc_bridge_command(sv, nil) == 0)
}
