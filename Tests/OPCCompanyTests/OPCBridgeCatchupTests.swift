import Foundation
import Testing

@testable import OPCCompanyCore

// v1.9 `catchup_md` over the real @_cdecl ABI. The door tests prove the
// composition; this file proves the CHANNEL: the page rides last_error
// as a plain UTF-8 string (not JSON — the page IS the payload), payload
// knobs pass through, repeat reads are byte-identical (no wall-clock
// inside), and the unknown-verb refusal stays shut next to the new case.
// NO fresh-empty asserts: the runner's support dir is process-shared
// (see OPCBridgeStandupWindowTests) — every seed here is saved
// IN-PROCESS before create, so the door sees exactly this state.

@MainActor
private func seedCatchUp(now: Date) throws -> CompanyStore {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    let alice = store.agents.first!.id
    store.events = [
        CompanyEvent(productID: pid, kind: .taskCreated, title: "新活", detail: "d",
                     createdAt: now.addingTimeInterval(-3600)),
    ]
    store.approvals = [
        ApprovalRequest(productID: pid, requesterID: alice, title: "等你批",
                        reason: "r", status: .pending,
                        createdAt: now.addingTimeInterval(-120)),
    ]
    store.saveSnapshot()
    return store
}

@MainActor
@Test func bridgeCatchupContractOverRealABI() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("opc-catchup-bridge-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    setenv("OPC_COMPANY_SUPPORT_DIR", tmp.path, 1)
    defer { unsetenv("OPC_COMPANY_SUPPORT_DIR") }

    _ = try seedCatchUp(now: Date())

    #expect(opc_bridge_create() == 0)
    defer { opc_bridge_destroy() }
    let verb = strdup("catchup_md")
    defer { free(verb) }

    #expect(opc_bridge_command(verb, nil) == 0)
    let page = String(cString: try #require(opc_bridge_last_error()))

    // the page IS the payload: plain markdown, every section in order
    for marker in ["# Catch-up — ", "## Traffic (last 24h)", "## Who did what",
                   "## Stuck (parked over 30 min)", "## Waiting on you (1)",
                   "## Shelf integrity", "Pure read — this page wrote nothing."] {
        #expect(page.contains(marker), "section missing from the channel: \(marker)")
    }
    #expect(page.contains("等你批"), "the desk names the pending row")

    // byte-stability: a second read of the same state is byte-identical
    #expect(opc_bridge_command(verb, nil) == 0)
    let again = String(cString: try #require(opc_bridge_last_error()))
    #expect(page == again, "no wall-clock inside: repeat channel reads are byte-stable")

    // payload knobs: hours/over_minutes pass through to the section text
    let payload = strdup("{\"hours\":5,\"over_minutes\":10}")
    defer { free(payload) }
    #expect(opc_bridge_command(verb, payload) == 0)
    let tuned = String(cString: try #require(opc_bridge_last_error()))
    #expect(tuned.contains("## Traffic (last 5h)"))
    #expect(tuned.contains("## Stuck (parked over 10 min)"))

    // the ABI's refusal discipline is untouched next to the new case
    let junk = strdup("not_a_verb")
    defer { free(junk) }
    #expect(opc_bridge_command(junk, nil) == -1)
}
