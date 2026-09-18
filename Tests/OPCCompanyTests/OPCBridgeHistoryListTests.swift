import Foundation
import Testing

@testable import OPCCompanyCore

// v1.4 `history_list` over the real @_cdecl ABI — same contract discipline
// approvals_list earned: registered, rc=0 with a JSON ARRAY payload, and
// read-only (no support-dir drift, idempotent, write-guard untripped).
// Row content is pinned at the store level (selectedProductResolved-
// Approvals ordering) and live in scripts/ffi-e2e.sh — this file pins the
// ABI door only. Isolation: fresh empty support dir, never the user's.

@MainActor
@Test func bridgeHistoryListContractOverRealABI() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("opc-history-list-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    setenv("OPC_COMPANY_SUPPORT_DIR", tmp.path, 1)
    defer { unsetenv("OPC_COMPANY_SUPPORT_DIR") }

    #expect(opc_bridge_create() == 0)
    defer { opc_bridge_destroy() }

    let verb = strdup("history_list")
    defer { free(verb) }

    // registered verb, fresh company: success + empty JSON array ledger
    #expect(opc_bridge_command(verb, nil) == 0)
    let payload = String(cString: try #require(opc_bridge_last_error()))
    #expect(payload == "[]", "a fresh company has decided nothing, got \(payload)")

    // array-shaped AND array-typed: parseable, and NOT an object (the
    // v1.4 payload is a list — the same shape rule as approvals_list)
    let parsed = try JSONSerialization.jsonObject(with: Data(payload.utf8))
    #expect(parsed as? [Any] != nil)

    // idempotent + read-only: repeats answer identically and touch nothing
    #expect(opc_bridge_command(verb, nil) == 0)
    let again = String(cString: try #require(opc_bridge_last_error()))
    #expect(again == payload)
    let before = try contentsOf(tmp)
    _ = opc_bridge_command(verb, nil)
    #expect(try contentsOf(tmp) == before,
            "a query verb must not touch the support dir")

    // unregistered verbs STILL refuse (history_list must not have widened
    // the unknown-verb hole it sits next to)
    let junk = strdup("history_listx")
    defer { free(junk) }
    #expect(opc_bridge_command(junk, nil) == -1)

    // queries leave the write path clean: save succeeds right after
    let sv = strdup("save")
    defer { free(sv) }
    #expect(opc_bridge_command(sv, nil) == 0)
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
