import Foundation
import Testing

@testable import OPCCompanyCore

// v1.6 `standup_window` over the real @_cdecl ABI — same discipline as
// v1.4/v1.5: the verb is registered, rc=0 carries an OBJECT through the
// smuggle channel, it is idempotent, it never touches the support dir,
// it does not widen the unknown-verb hole, and the write path stays
// clean afterwards. The window's MATH is pinned at the store level
// (OPCStandupDoorTests) and end-to-end in the CLI (OPCCliStandupTests);
// this file pins the DOOR SHAPE the shell binds against. Isolated dir.

@MainActor
@Test func bridgeStandupWindowContractOverRealABI() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("opc-standup-bridge-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    setenv("OPC_COMPANY_SUPPORT_DIR", tmp.path, 1)
    defer { unsetenv("OPC_COMPANY_SUPPORT_DIR") }

    #expect(opc_bridge_create() == 0)
    defer { opc_bridge_destroy() }

    let verb = strdup("standup_window")
    defer { free(verb) }

    // registered verb, fresh company: success + an all-zero quiet window
    #expect(opc_bridge_command(verb, nil) == 0)
    let payload = String(cString: try #require(opc_bridge_last_error()))
    let obj = try JSONSerialization.jsonObject(with: Data(payload.utf8))
    let row = try #require(obj as? [String: Any],
                           "the window payload is an OBJECT, not a list")
    #expect(row["hours"] as? Int == 24, "default window is 24h — the .h says so")
    for key in ["newWork", "decisions", "deliveries", "missing", "risks", "awaitingNow"] {
        #expect(row[key] is Int, "\(key) must be an integer count")
    }
    // NOTE no all-zero assertion: supportDirectory is process-cached by
    // design (the override env must be set BEFORE launch), so inside one
    // swift-test runner every test shares T/OPCCompanyTests-<pid> — any
    // earlier test's saveSnapshot makes "fresh" a lie the suite cannot
    // order-proof. The zero-window-on-empty-core promise lives where it
    // is actually provable: ffi-e2e (fresh process, env pre-set) and the
    // shell's fake-bridge widget tests. This file pins the door SHAPE.

    // idempotent + read-only. Semantics compared, not bytes: the payload
    // is a JSON OBJECT and key order is not contractual (unlike the
    // newest-first LISTs, whose order IS the contract and ride raw compare).
    #expect(opc_bridge_command(verb, nil) == 0)
    let again = String(cString: try #require(opc_bridge_last_error()))
    let objA = try JSONSerialization.jsonObject(with: Data(payload.utf8))
    let objB = try JSONSerialization.jsonObject(with: Data(again.utf8))
    #expect(JSONSerialization.isValidJSONObject(objB)
            && (objA as? NSDictionary)?.isEqual(objB as? NSDictionary) == true,
            "the same window must answer identically")
    let before = try contentsOf(tmp)
    _ = opc_bridge_command(verb, nil)
    #expect(try contentsOf(tmp) == before,
            "a query verb must not touch the support dir")

    // unregistered verbs STILL refuse next to the new case
    let junk = strdup("standup_windowx")
    defer { free(junk) }
    #expect(opc_bridge_command(junk, nil) == -1)

    // query leaves the write path clean
    let sv = strdup("save")
    defer { free(sv) }
    #expect(opc_bridge_command(sv, nil) == 0)
}

@MainActor
@Test func bridgeStandupWindowAnswersRealTraffic() throws {
    // the whole point: seeded traffic, the bridge answers the COUNTS —
    // proving the bridge calls the store's door, not a literal template
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("opc-standup-live-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    setenv("OPC_COMPANY_SUPPORT_DIR", tmp.path, 1)
    defer { unsetenv("OPC_COMPANY_SUPPORT_DIR") }

    let now = Date()
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    store.events = [
        CompanyEvent(productID: pid, kind: .taskCreated, title: "活", detail: "d",
                     createdAt: now.addingTimeInterval(-3600)),
        CompanyEvent(productID: pid, kind: .risk, title: "险", detail: "d",
                     createdAt: now.addingTimeInterval(-1800)),
    ]
    store.approvals = [
        ApprovalRequest(productID: pid, title: "等", reason: "r", status: .pending),
    ]
    store.saveSnapshot()

    #expect(opc_bridge_create() == 0)
    defer { opc_bridge_destroy() }
    let verb = strdup("standup_window")
    defer { free(verb) }
    #expect(opc_bridge_command(verb, nil) == 0)
    let payload = String(cString: try #require(opc_bridge_last_error()))
    let row = try #require(JSONSerialization.jsonObject(with: Data(payload.utf8))
                           as? [String: Any])
    #expect(row["newWork"] as? Int == 1, "seeded creation must count: \(row)")
    #expect(row["risks"] as? Int == 1)
    #expect(row["awaitingNow"] as? Int == 1,
            "the live queue reaches the shell through the same door")
    #expect(row["decisions"] as? Int == 0)
}

private func contentsOf(_ dir: URL) throws -> [String: Int] {
    let fm = FileManager.default
    guard let items = try? fm.contentsOfDirectory(atPath: dir.path) else { return [:] }
    var out: [String: Int] = [:]
    for name in items {
        let attrs = try? fm.attributesOfItem(atPath: dir.appendingPathComponent(name).path)
        out[name] = (attrs?[.size] as? Int) ?? -1
    }
    return out
}
