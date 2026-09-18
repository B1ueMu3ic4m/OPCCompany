import Foundation
import Testing

@testable import OPCCompanyCore

// v1.3 `approvals_list` over the real @_cdecl ABI — the CONTRACT half the
// suite owes it: registered (no longer "unknown"), rc=0 with a JSON ARRAY
// (the only array-carrying verb) on a fresh company, and read-only (zero
// snapshot drift, side-effect-free on repeat). Row CONTENT is pinned
// elsewhere on purpose: the store-level filter lives in
// OPCOfficeApprovalQueryTests (pendingApprovals shares its source), and
// a live end-to-end round-trip runs in scripts/ffi-e2e.sh on both
// platforms — duplicating fixtures here would only invent a third source
// of truth.
//
// Isolation: fresh empty support dir (OPCBridgeStressTests' discipline) —
// never the user's snapshot.

@MainActor
@Test func bridgeApprovalsListContractOverRealABI() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("opc-approvals-list-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    setenv("OPC_COMPANY_SUPPORT_DIR", tmp.path, 1)
    defer { unsetenv("OPC_COMPANY_SUPPORT_DIR") }

    #expect(opc_bridge_create() == 0)
    defer { opc_bridge_destroy() }

    let v = strdup("approvals_list")
    defer { free(v) }

    // registered verb on a fresh company: success, empty ARRAY payload
    #expect(opc_bridge_command(v, nil) == 0)
    guard let err = opc_bridge_last_error() else { Issue.record("null error buffer"); return }
    let payload = String(cString: err)
    #expect(payload == "[]", "fresh company carries no pending approvals, got \(payload)")

    // the payload really is JSON-parseable as an array (not array-shaped text)
    let parsed = try JSONSerialization.jsonObject(with: Data(payload.utf8))
    #expect(parsed as? [Any] != nil)

    // read-only & idempotent: repeat calls answer identically…
    #expect(opc_bridge_command(v, nil) == 0)
    let again = String(cString: try #require(opc_bridge_last_error()))
    #expect(again == payload)

    // …and never mutate the on-disk state: file set stays as create left it
    let before = try contentsOfSupportDir(tmp)
    _ = opc_bridge_command(v, nil)
    let after = try contentsOfSupportDir(tmp)
    #expect(before == after, "a query verb must not touch the support dir")

    // the write-guard is not tripped by queries: a save still succeeds
    // right after approvals_list (proof the verb skipped ensureExclusive…)
    let sv = strdup("save")
    defer { free(sv) }
    #expect(opc_bridge_command(sv, nil) == 0)
}

private func contentsOfSupportDir(_ dir: URL) throws -> [String: Int] {
    let fm = FileManager.default
    guard let items = try? fm.contentsOfDirectory(atPath: dir.path) else { return [:] }
    var out: [String: Int] = [:]
    for name in items {
        let attrs = try? fm.attributesOfItem(atPath: dir.appendingPathComponent(name).path)
        out[name] = (attrs?[.size] as? Int) ?? -1
    }
    return out
}
