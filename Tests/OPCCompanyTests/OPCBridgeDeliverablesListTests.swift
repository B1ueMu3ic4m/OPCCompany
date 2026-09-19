import Foundation
import Testing

@testable import OPCCompanyCore

// v1.5 `deliverables_list` over the real @_cdecl ABI — same discipline as
// history_list: the door is registered, answers rc=0 with a JSON ARRAY,
// is idempotent, never touches the support dir, never widens the
// unknown-verb hole, and leaves the write path clean. Row content
// (existsNow computed live, delivery-view order) is pinned at the store
// level (OPCDeliveryShelfTests) and end-to-end via the CLI subprocess
// (OPCCliDeliverablesTests) + scripts/ffi-e2e.sh. Isolated support dir.

@MainActor
@Test func bridgeDeliverablesListContractOverRealABI() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("opc-deliverables-list-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    setenv("OPC_COMPANY_SUPPORT_DIR", tmp.path, 1)
    defer { unsetenv("OPC_COMPANY_SUPPORT_DIR") }

    #expect(opc_bridge_create() == 0)
    defer { opc_bridge_destroy() }

    let verb = strdup("deliverables_list")
    defer { free(verb) }

    // registered verb, fresh company: success + empty JSON array shelf
    #expect(opc_bridge_command(verb, nil) == 0)
    let payload = String(cString: try #require(opc_bridge_last_error()))
    #expect(payload == "[]", "a fresh company delivered nothing, got \(payload)")

    let parsed = try JSONSerialization.jsonObject(with: Data(payload.utf8))
    #expect(parsed as? [Any] != nil, "the shelf payload is a LIST, not an object")

    // idempotent + read-only: repeats answer identically and touch nothing
    #expect(opc_bridge_command(verb, nil) == 0)
    let again = String(cString: try #require(opc_bridge_last_error()))
    #expect(again == payload)
    let before = try contentsOf(tmp)
    _ = opc_bridge_command(verb, nil)
    #expect(try contentsOf(tmp) == before,
            "a query verb must not touch the support dir")

    // unregistered verbs STILL refuse next to the new case
    let junk = strdup("deliverables_listx")
    defer { free(junk) }
    #expect(opc_bridge_command(junk, nil) == -1)

    // queries leave the write path clean: save succeeds right after
    let sv = strdup("save")
    defer { free(sv) }
    #expect(opc_bridge_command(sv, nil) == 0)
}

@MainActor
@Test func bridgeDeliverablesRowFlipsWithoutAnyWrite() throws {
    // existsNow is the WHOLE point of v1.5 — a shell row must flip
    // [OK]->[MISSING] between two calls with ZERO state changes: same
    // bridge, same store, one deleted file. Isolated dir; the artifact
    // points at a scratch file the test controls.
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("opc-shelf-flip-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    setenv("OPC_COMPANY_SUPPORT_DIR", tmp.path, 1)
    defer { unsetenv("OPC_COMPANY_SUPPORT_DIR") }

    let claim = tmp.appendingPathComponent("shipped.md")
    try "x".data(using: .utf8)!.write(to: claim)
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.artifacts.append(ArtifactRecord(productID: store.selectedProductID,
        kind: .report, title: "flip", path: claim.path, summary: "s"))
    store.saveSnapshot()

    #expect(opc_bridge_create() == 0)
    defer { opc_bridge_destroy() }
    let verb = strdup("deliverables_list")
    defer { free(verb) }

    #expect(opc_bridge_command(verb, nil) == 0)
    var rows = try rowsFrom(String(cString: try #require(opc_bridge_last_error())))
    #expect(rows.count == 1)
    #expect(rows[0]["existsNow"] as? Bool == true, "the file is there NOW")

    // kill the file; ask the SAME door again — no writes, no re-create
    try FileManager.default.removeItem(at: claim)
    #expect(opc_bridge_command(verb, nil) == 0)
    rows = try rowsFrom(String(cString: try #require(opc_bridge_last_error())))
    #expect(rows[0]["existsNow"] as? Bool == false,
            "the verdict is a LIVE read, not a stored claim: \(rows[0])")
}

private func rowsFrom(_ payload: String) throws -> [[String: Any]] {
    let parsed = try JSONSerialization.jsonObject(with: Data(payload.utf8))
    return parsed as? [[String: Any]] ?? []
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
