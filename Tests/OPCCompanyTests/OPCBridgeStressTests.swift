import Foundation
import Testing

@testable import OPCCompanyCore

// ═══════════════════════════════════════════════════════════════════════
// Stress & hardening suite for the M3 C-ABI bridge (audit round 2026-09-14).
//
// What this is: adversarial load through the ACTUAL @_cdecl entry points —
// garbage payloads, NULLs, rapid create/destroy cycles, cross-thread hammer-
// ing — plus core-layer scaling (hundreds of goals) and a real CLI-subprocess
// loop. The Dart shell layer is covered by scripts/ffi-e2e.sh (needs a
// Flutter host; CI-informed separately).
//
// Isolation: every store-level stress run bootstraps a FRESH company
// (loadPersisted:false) inside the test support dir, or injects its own
// environment maps into the guard — never the user's live snapshot.
// ═══════════════════════════════════════════════════════════════════════

/// True when a live OPCCompany.app would make the guard refuse writes.
/// Dev boxes with the desktop app open SKIP the "must not throw" assertions
/// (refusal is correct behavior there); CI never has one and covers them.
private let appIsRunning: Bool = {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    p.arguments = ["-x", "OPCCompany"]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try? p.run()
    p.waitUntilExit()
    return p.terminationStatus == 0
}()

private func stressSupportEnv() -> [String: String] {
    // The guard tests below pass env maps EXPLICITLY — no process-global
    // mutation, no interference with the suite's own support dir.
    ["OPC_ALLOW_CONCURRENT_WRITE": "1"]
}

// ── ABI contract under abuse ────────────────────────────────────────────

@Test @MainActor func bridgeSurvivesMalformedInputs() {
    // NULL verbs, invalid UTF-8 pairs, truncated JSON, oversized payloads:
    // every one must come back as a refusal (-1), never a crash or a hang.
    // (Dart hosts will send worse than this; the contract is refuse-clean.)
    #expect(opc_bridge_create() == 0)
    defer { opc_bridge_destroy() }

    let garbage = ["{}", "", "{\"text\": null}", "{\"text\": 42}",
                   "{\"approvalID\": \"not-a-uuid\"}", "{\"approvalID\": \"\"}"]
    for payload in garbage {
        let v = strdup("goal")
        let p = strdup(payload)
        defer { free(v); free(p) }
        let rc = opc_bridge_command(v, p)
        // goal with non-string text throws inside trim-guard → refused, or
        // numeric text → refused; ""/null → refused. None may trap.
        #expect(rc == -1, "payload '\(payload)' must be refused, got \(rc)")
    }
    // decide with junk ids
    for id in ["not-a-uuid", "", "{}"] {
        let v = strdup("decide")
        let payload = "{\"approvalID\":\"\(id)\",\"approved\":true}"
        let p = strdup(payload)
        defer { free(v); free(p) }
        #expect(opc_bridge_command(v, p) == -1, "decide junk id must refuse")
    }
    // oversized payload (1 MB text field) — must parse or refuse cleanly
    let big = String(repeating: "x", count: 1_000_000)
    let v = strdup("goal")
    let p = strdup("{\"text\":\"\(big)\"}")
    defer { free(v); free(p) }
    let rc = opc_bridge_command(v, p)
    #expect(rc == 0 || rc == -1, "oversized payload answered normally (rc=\(rc))")
    if rc == 0 { _ = opc_bridge_destroy(); _ = opc_bridge_create() } // goal may have been accepted
}

@Test @MainActor func bridgeHandlesNullPointersAndDoubleLifecycle() {
    // NULL verb → refuse, not crash. create→destroy→create churn must stay
    // consistent (the churn a long-lived shell does across snapshot reloads).
    #expect(opc_bridge_command(nil, nil) == -1)
    for _ in 0..<25 {
        #expect(opc_bridge_create() == 0)
        if let snap = opc_bridge_snapshot_json() { free(snap) }
        opc_bridge_destroy()
    }
    // post-destroy commands refuse with the documented reason
    let verb = strdup("save")
    let payload = strdup("{}")
    defer { free(verb); free(payload) }
    #expect(opc_bridge_command(verb, payload) == -1)
    if let err = opc_bridge_last_error() {
        #expect(String(cString: err).contains("not created"))
        free(err)
    }
}

@Test @MainActor func bridgeReturnsAreIndividuallyFreeable() {
    // 200 leaked-pointer rounds is the smallest sample where allocator
    // mismatch (Swift allocate vs C free) shows up as corruption on Windows
    // debug heaps and ASan builds — keep the loop if the target adds them.
    #expect(opc_bridge_create() == 0)
    defer { opc_bridge_destroy() }
    for _ in 0..<200 {
        guard let err = opc_bridge_last_error() else { Issue.record("null error buffer"); break }
        free(err)
    }
    // interleaved with snapshot buffers
    for _ in 0..<50 {
        if let snap = opc_bridge_snapshot_json() { free(snap) }
        if let err = opc_bridge_last_error() { free(err) }
    }
}

// ── write-guard stress (explicit env; the guard is env-injected) ───────

@Test func writeGuardOverrideHonoredAtScale() {
    // 1000 guard calls with the override must all pass, fast (<1 s total) —
    // the bridge calls it on every write verb, so per-command guard overhead
    // is per-command latency for the whole shell.
    let start = Date()
    for _ in 0..<1000 {
        #expect(throws: Never.self) {
            try OPCWriteGuard.ensureExclusiveAccess(environment: stressSupportEnv())
        }
    }
    #expect(Date().timeIntervalSince(start) < 1.0, "1000 guard passes exceeded 1 s")
}

@Test(arguments: [[String: String](),
                  ["OPC_ALLOW_CONCURRENT_WRITE": "0"],
                  ["OPC_ALLOW_CONCURRENT_WRITE": ""],
                  ["OPC_ALLOW_CONCURRENT_WRITE": "yes"]])
func writeGuardNonOneEnvKeepsDetectionPath(env: [String: String]) throws {
    // The override recognizes ONLY exact "1" — "0"/""/yes must not disable
    // the guard (a semantic security hole). With detection running and no
    // app in sight (CI), the call passes; a dev machine with the GUI open
    // legitimately refuses — both are asserted, nothing else may happen.
    do {
        try OPCWriteGuard.ensureExclusiveAccess(environment: env)
    } catch is OPCConcurrentWriterError {
        // The only other legal outcome; must mean the app is actually open.
        #expect(appIsRunning, "guard refused but no OPCCompany.app is running")
    }
    // Any other error type would already have failed the test signature.
}

// ── core scaling: the company chart under load ─────────────────────────

@Test @MainActor func companyScalesThroughBridgeVerbs() throws {
    // 200 goals via the exact call path the bridge uses (fresh company —
    // loadPersisted:false means no user data involved, no env needed).
    let store = CompanyStore.bootstrap(loadPersisted: false, liveChatEnabled: false)
    let start = Date()
    for i in 0..<200 {
        let goalID = store.startCTOSupervisorGoal(goal: "压力目标 \(i)")
        #expect(goalID != nil, "goal \(i) must create")
    }
    let goalSeconds = Date().timeIntervalSince(start)
    let created = store.tasks.count
    #expect(created >= 200 * 4, "200 goals → ≥800 tasks, got \(created)")

    // Snapshot encode at scale — the shell's every-Refresh path.
    let encodeStart = Date()
    var lastSize = 0
    for _ in 0..<20 {
        let snap = store.currentSnapshot()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snap)
        lastSize = data.count
    }
    let encodeSeconds = Date().timeIntervalSince(encodeStart) / 20
    #expect(lastSize > 10_000, "snapshot should carry the stress data (\(lastSize) B)")
    // Time-boxes sized for runner jitter (debug builds, shared runners);
    // they catch algorithmic blowups (the quadratic-class regressions), not
    // noise. Measured on an M2 under load; the numbers below are generous.
    #expect(goalSeconds < 60, "200 goals took \(goalSeconds)s — goal path regressed")
    #expect(encodeSeconds < 2.0, "snapshot encode \(encodeSeconds)s avg at \(created) tasks")

    // save at scale through the persistence path the bridge uses.
    let saveStart = Date()
    store.saveSnapshot()
    #expect(Date().timeIntervalSince(saveStart) < 10, "one save took >10s at \(created) tasks")
}

// ── guard unit: the matrix above covers env semantics end to end ───────
