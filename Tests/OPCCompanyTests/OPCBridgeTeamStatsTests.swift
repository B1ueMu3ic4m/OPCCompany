import Foundation
import Testing

@testable import OPCCompanyCore

// v1.7 `team_stats_list` over the real @_cdecl ABI. Shape + ordering +
// hours math + the read-time existence flip. NO fresh-empty asserts:
// the runner's support dir is process-shared by design (see
// OPCBridgeStandupWindowTests note) — every seed is saved IN-PROCESS
// before create, so this file controls exactly what the door sees.

private func rowsFrom(_ payload: String) throws -> [[String: Any]] {
    let parsed = try JSONSerialization.jsonObject(with: Data(payload.utf8))
    return parsed as? [[String: Any]] ?? []
}

@MainActor
private func seedTeam(now: Date) throws -> (CompanyStore, UUID) {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    let alice = store.agents.first!.id
    store.events = [
        CompanyEvent(productID: pid, kind: .taskAssigned, title: "e", detail: "d",
                     agentID: alice, createdAt: now.addingTimeInterval(-3600)),
        // 25h: outside the default window, inside a 48h one
        CompanyEvent(productID: pid, kind: .risk, title: "e", detail: "d",
                     agentID: alice, createdAt: now.addingTimeInterval(-25 * 3600)),
    ]
    store.tasks = []
    store.artifacts = []
    store.approvals = []
    store.saveSnapshot()
    return (store, alice)
}

@MainActor
@Test func bridgeTeamStatsContractOverRealABI() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("opc-team-bridge-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    setenv("OPC_COMPANY_SUPPORT_DIR", tmp.path, 1)
    defer { unsetenv("OPC_COMPANY_SUPPORT_DIR") }

    let now = Date()
    let (store, alice) = try seedTeam(now: now)
    let aliceName = store.agents.first!.displayName

    #expect(opc_bridge_create() == 0)
    defer { opc_bridge_destroy() }

    let verb = strdup("team_stats_list")
    defer { free(verb) }

    // default window: the 25h risk must NOT be there
    #expect(opc_bridge_command(verb, nil) == 0)
    let rows = try rowsFrom(String(cString: try #require(opc_bridge_last_error())))
    let a = try #require(rows.first { ($0["agentID"] as? String) == alice.uuidString },
                         "the door must answer alice: \(rows)")
    #expect(a["name"] as? String == aliceName)
    #expect(a["assigned"] as? Int == 1)
    #expect(a["risks"] as? Int == 0, "window math runs INSIDE the door: \(a)")
    for key in ["deliveries", "missing", "asked", "activeNow"] {
        #expect(a[key] is Int, "\(key) must be an integer count")
    }

    // the door is deterministic: two SEPARATE calls must agree byte for
    // byte (arrays ride raw compare — order IS the contract for lists,
    // unlike the v1.6 object). Read each sample right after ITS call;
    // reading last_error twice around one call compares the same buffer
    // twice and passes vacuously (v0.10 probe lesson).
    let first = String(cString: try #require(opc_bridge_last_error()))
    #expect(opc_bridge_command(verb, nil) == 0)
    let again = String(cString: try #require(opc_bridge_last_error()))
    #expect(again == first, "same store, same list, same bytes")

    // hours arrives through the payload
    let p = strdup("{\"hours\":48}")
    defer { free(p) }
    #expect(opc_bridge_command(verb, p) == 0)
    let wide = try rowsFrom(String(cString: try #require(opc_bridge_last_error())))
    let aw = try #require(wide.first { ($0["agentID"] as? String) == alice.uuidString })
    #expect(aw["risks"] as? Int == 1, "the 48h window must let the 25h risk in")

    // unregistered neighbors STILL refuse (the hole can't widen)
    let junk = strdup("team_stats_listx")
    defer { free(junk) }
    #expect(opc_bridge_command(junk, nil) == -1)

    // the query left the write path clean
    let sv = strdup("save")
    defer { free(sv) }
    #expect(opc_bridge_command(sv, nil) == 0)
}

@MainActor
@Test func bridgeTeamStatsGhostFlipsAndUnattributedSortsLast() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("opc-team-ghost-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    setenv("OPC_COMPANY_SUPPORT_DIR", tmp.path, 1)
    defer { unsetenv("OPC_COMPANY_SUPPORT_DIR") }

    let now = Date()
    let (store, alice) = try seedTeam(now: now)
    let claim = tmp.appendingPathComponent("shipped.md")
    try "x".data(using: .utf8)!.write(to: claim)
    var task = CompanyTask(productID: store.selectedProductID, title: "T",
                           ownerID: alice, status: .running, successCriteria: "s")
    store.tasks = [task]
    task = store.tasks[0]
    store.artifacts = [
        ArtifactRecord(productID: store.selectedProductID, taskID: task.id,
                       kind: .report, title: "ghost", path: claim.path,
                       summary: "s", createdAt: now.addingTimeInterval(-900)),
        // dead chain: task id points at nothing -> unattributed row
        ArtifactRecord(productID: store.selectedProductID, taskID: UUID(),
                       kind: .report, title: "orphan", path: claim.path,
                       summary: "s", createdAt: now.addingTimeInterval(-900)),
    ]
    store.saveSnapshot()

    #expect(opc_bridge_create() == 0)
    defer { opc_bridge_destroy() }
    let verb = strdup("team_stats_list")
    defer { free(verb) }

    #expect(opc_bridge_command(verb, nil) == 0)
    var rows = try rowsFrom(String(cString: try #require(opc_bridge_last_error())))
    let a = try #require(rows.first { ($0["agentID"] as? String) == alice.uuidString })
    #expect(a["deliveries"] as? Int == 1 && a["missing"] as? Int == 0,
            "file exists NOW: \(a)")
    let un = try #require(rows.first { $0["agentID"] == nil },
                          "the orphan artifact earns the named bucket: \(rows)")
    #expect(un["name"] as? String == "未分配")
    #expect(un["deliveries"] as? Int == 1)
    #expect(rows.last?["agentID"] == nil, "unattributed is ALWAYS last")

    // kill the file; the SAME door flips the row, zero writes
    try FileManager.default.removeItem(at: claim)
    #expect(opc_bridge_command(verb, nil) == 0)
    rows = try rowsFrom(String(cString: try #require(opc_bridge_last_error())))
    let a2 = try #require(rows.first { ($0["agentID"] as? String) == alice.uuidString })
    #expect(a2["missing"] as? Int == 1, "live verdict, not a stored claim: \(a2)")
}
