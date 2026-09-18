import Foundation
import Testing

@testable import OPCCompanyCore

// ── R3 boundary probes: the store's two unbounded surfaces.
// (1) Terminal logs grow forever per agent·product — what does a ~2 MB log
// do to append cost, the digest computation, and the snapshot round-trip?
// The shell re-parses the snapshot JSON on its UI isolate, so an oversized
// blob that fails to encode/decode (or takes minutes) is a real crash
// class, not a perf nit.
// (2) 100 products: creation + selection sweep + save/load at scale. The
// 200-goals test pins task scaling; nobody had pinned product scaling.
// Budgets are deliberately generous (they catch regressions/accidents,
// not exact perf — CI runners are noisy).
//
// STATE-NEUTRAL (R2 lesson): saveSnapshot writes the SUITE's shared temp
// support dir; a leaked 2 MB state file would poison every later
// bootstrap(loadPersisted: true) test at a distance. Both tests capture
// the prior bytes and restore (or delete) on exit.

/// Run `body`, then restore the suite state file to its prior bytes.
@MainActor
private func withStateRestore(_ body: () throws -> Void) throws {
    let stateFile = CompanyPersistence.supportDirectory
        .appendingPathComponent("company-state.json")
    let prior = try? Data(contentsOf: stateFile)
    defer {
        if let prior {
            try? prior.write(to: stateFile)
        } else {
            try? FileManager.default.removeItem(at: stateFile)
        }
    }
    try body()
}

@Test @MainActor func oversizedTerminalLogsStayCheapAndRoundTrip() throws {
    // WriteGuard's pgrep spawn is covered at scale elsewhere
    // (writeGuardOverrideHonoredAtScale); skip it here so the timing
    // measures the store, not process spawning.
    setenv("OPC_ALLOW_CONCURRENT_WRITE", "1", 1)
    defer { unsetenv("OPC_ALLOW_CONCURRENT_WRITE") }

    try withStateRestore {
        let store = CompanyStore.bootstrap(loadPersisted: false,
                                           liveChatEnabled: false)
        let agentID = store.ctoID

        // Growth must stay amortized-cheap — a re-copy-per-append
        // implementation would die here.
        let chunk = String(repeating: "0123456789 日志行 log line\n", count: 200) // ~6.6 KB
        let t0 = Date()
        for _ in 0..<400 {
            store.appendTerminalLog(chunk, for: agentID)
        }
        let appendSecs = Date().timeIntervalSince(t0)
        let log = store.productTerminalLogs[
            store.terminalLogStorageKey(productID: store.selectedProductID,
                                        agentID: agentID)] ?? ""
        #expect(log.utf8.count >= 2_000_000,
                "log only reached \(log.utf8.count) B — append silently dropped?")
        #expect(appendSecs < 10, "2 MB of appends took \(appendSecs)s — quadratic append?")

        // The digest verb's contract (mirrors OPCBridge's "terminal_digest"
        // branch exactly): byte lengths keyed by agentID, prefix-filtered
        // to the selected product — O(logs) measuring, never O(bytes)
        // copying, and structurally incapable of cross-product bleed.
        let prefix = store.selectedProductID.uuidString.lowercased() + ":"
        let t1 = Date()
        var digest: [String: Int] = [:]
        for (key, entry) in store.productTerminalLogs where key.hasPrefix(prefix) {
            digest[String(key.dropFirst(prefix.count))] = entry.utf8.count
        }
        let digestSecs = Date().timeIntervalSince(t1)
        #expect(digest[agentID.uuidString.lowercased()] == log.utf8.count,
                "digest lost the oversized log: \(digest)")
        #expect(digestSecs < 2,
                "digest took \(digestSecs)s on a 2 MB log — it must measure, not copy")

        // The snapshot must still save and re-parse at this size — the
        // shell JSON-decodes it on every window refresh.
        let t2 = Date()
        store.saveSnapshot()
        let saveSecs = Date().timeIntervalSince(t2)
        #expect(saveSecs < 30, "snapshot save took \(saveSecs)s at 2 MB log")
        let data = try Data(contentsOf: CompanyPersistence.supportDirectory
                            .appendingPathComponent("company-state.json"))
        #expect(data.count >= 2_000_000 && data.count < 8_000_000,
                "snapshot size off the rails: \(data.count) B")
        #expect(try JSONSerialization.jsonObject(with: data) is [String: Any])
    }
}

@Test @MainActor func productScalingSurvivesCreationSweepAndRoundTrip() throws {
    setenv("OPC_ALLOW_CONCURRENT_WRITE", "1", 1)
    defer { unsetenv("OPC_ALLOW_CONCURRENT_WRITE") }

    try withStateRestore {
        let store = CompanyStore.bootstrap(loadPersisted: false,
                                           liveChatEnabled: false)
        // Products through the REAL creation path (addProductWorkspace runs
        // team restart + root-directory creation — the expensive parts a
        // synthetic append would skip).
        let t0 = Date()
        for _ in 1...99 { store.addProductWorkspace() }
        let createSecs = Date().timeIntervalSince(t0)
        #expect(store.products.count >= 100,
                "only \(store.products.count) products after 99 adds")
        // Generous: each add touches the filesystem; slow CI disks exist.
        #expect(createSecs < 120, "99 real product creations took \(createSecs)s")

        let ids = store.products.map(\.id)
        let t1 = Date()
        for id in ids { store.selectProduct(id) }
        let switchSecs = Date().timeIntervalSince(t1)
        #expect(switchSecs < 90, "100-product selection sweep took \(switchSecs)s")
        #expect(store.selectedProductID == ids.last)

        // Round-trip: nothing may evaporate through save/load at scale.
        store.saveSnapshot()
        let reloaded = CompanyStore.bootstrap(loadPersisted: true,
                                              liveChatEnabled: false)
        #expect(reloaded.products.count >= 100,
                "products lost across round-trip: \(reloaded.products.count)")
        #expect(reloaded.selectedProductID == store.selectedProductID)
    }
}
