import Foundation
import Testing

@testable import OPCCompanyCore

// ── R3: the header promises "safe to call from ANY host thread" — proved
// here, and the proof pinned down the contract's ACTUAL precondition,
// twice. Design 1 ran the test body off-main: instant deadlock (the
// bridge hops to the host main queue; the runner's main thread was
// parked). Design 2 kept @MainActor but BLOCKED on RunLoop pumping in a
// while-loop — and Swift Testing's @MainActor test body, while it does
// occupy the real main thread (verified by probe: isMainThread == true),
// does not run the run loop in between; blocked main, deadlocked storm.
// Design 3 (here) mirrors the real GUI host exactly: an async main that
// AWAITs — which drives the main queue continuously — while 8 detached
// worker threads hammer the C ABI. That is Flutter's shape: platform
// thread pumps, Dart isolates call.
//
// Pinned properties:
//   1. interleaved verbs serialize: snapshot JSON is never torn, every
//      call returns 0 or -1 (never a trap, never garbage codes);
//   2. refusal reasons survive the lastError-slot race as WHOLE sentences
//      (malloc-copy-per-read atomicity; the slot may change between call
//      and read, the string may not fragment);
//   3. the v1.1 contract wording gains its missing clause: worker-thread
//      calls require a host whose main thread keeps servicing its queue
//      (any GUI does; a blocked main does not) — see include/opc_bridge.h.

@Test func bridgeIsSafeAndSerializedFromWorkerThreads() async throws {
    // Skip the per-save WriteGuard pgrep spawn (240 guard launches would
    // serialize on the host main queue and stretch a seconds-long storm
    // into minutes). Persistence stays safe: a test process resolves the
    // support dir to the temp-isolated OPCCompanyTests-<pid> location
    // (isLikelyTestProcess), never the real user snapshot — and the real
    // snapshot hash is re-checked by the suite gates after this test.
    setenv("OPC_ALLOW_CONCURRENT_WRITE", "1", 1)
    defer { unsetenv("OPC_ALLOW_CONCURRENT_WRITE") }

    #expect(opc_bridge_create() == 0, "bridge create failed before storm")
    defer { opc_bridge_destroy() }

    let workers = 8
    let iterations = 120
    let collector = StormCollector()

    // Launch the storm from detached tasks — these are exactly what a Dart
    // FFI call looks like from the bridge's point of view: a non-main
    // thread blocking on a main-queue hop.
    await withTaskGroup(of: Void.self) { group in
        for w in 0..<workers {
            group.addTask(priority: .userInitiated) {
                for i in 0..<iterations {
                    switch (w &+ i) % 4 {
                    case 0:
                        if let p = opc_bridge_snapshot_json() {
                            collector.absorbSnapshot(String(cString: p))
                            opc_bridge_free(p)
                        }
                    case 1:
                        let rc: Int32 = "save".withCString {
                            opc_bridge_command($0, nil)
                        }
                        // save may legitimately refuse (concurrent writer);
                        // it must NEVER return a garbage code.
                        #expect(rc == 0 || rc == -1, "save rc was \(rc)")
                    case 2:
                        _ = "terminal_digest".withCString {
                            opc_bridge_command($0, nil)
                        }
                        if let p = opc_bridge_last_error() {
                            collector.observeError(String(cString: p))
                            opc_bridge_free(p)
                        }
                    default:
                        let rc: Int32 = "bogus_verb".withCString { v in
                            "{}".withCString { p in
                                opc_bridge_command(v, p)
                            }
                        }
                        #expect(rc == -1, "bogus verb must refuse, rc=\(rc)")
                    }
                }
            }
        }
        // The current task's awaits keep the main queue live while the
        // detached storm hops through it — the GUI-host shape, no blocking,
        // no runloop hacks, no timers.
        await group.waitForAll()
    }

    let snaps = collector.snapshots
    #expect(snaps.count > workers,
            "only \(snaps.count) snapshots collected — hops starved?")
    for s in snaps {
        let obj = try? JSONSerialization.jsonObject(with: Data(s.utf8))
        #expect(obj != nil, "snapshot JSON torn: \(s.prefix(80))")
    }
    for e in collector.errors {
        let plausible = e.isEmpty
            || e.hasPrefix("{") // digest envelope JSON payload
            || e.contains("unknown bridge verb")
            || e.contains("already decided")
            || e.contains("no approval with id")
            || e.contains("no product with id")
            || e.contains("concurrent")
            || e.contains("no product selected")
        #expect(plausible, "torn refusal reason: \(e.prefix(120))")
    }

    // ABI discipline after the storm: clean destroy, working re-create.
    opc_bridge_destroy()
    #expect(opc_bridge_create() == 0, "bridge could not be re-created")
    opc_bridge_destroy()
}

/// Thread-safe capture of strings observed by the storm (capped so a
/// ~1000-call storm cannot balloon memory in the runner).
private final class StormCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _snapshots: [String] = []
    private var _errors: [String] = []
    var snapshots: [String] { lock.lock(); defer { lock.unlock() }; return _snapshots }
    var errors: [String] { lock.lock(); defer { lock.unlock() }; return _errors }
    func absorbSnapshot(_ s: String) {
        lock.lock(); if _snapshots.count < 256 { _snapshots.append(s) }; lock.unlock()
    }
    func observeError(_ s: String) {
        lock.lock(); if _errors.count < 256 { _errors.append(s) }; lock.unlock()
    }
}
