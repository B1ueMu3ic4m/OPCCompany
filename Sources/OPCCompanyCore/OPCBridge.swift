#if canImport(Darwin)
import Darwin
#elseif canImport(WinSDK)
import WinSDK
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

// ═══════════════════════════════════════════════════════════════════════
// OPCBridge — the C-ABI surface of the portable core (Milestone M3).
//
// One core, many shells: the macOS/SwiftUI app and the `opc` CLI already
// consume CompanyStore as a Swift library; this file exposes the SAME store
// through a plain-C ABI so the planned Flutter (dart:ffi) Windows/Linux
// desktop shell can drive it without any Swift runtime knowledge.
//
// Design (deliberately minimal, JSON over the boundary):
//   - lifecycle: opc_bridge_create / opc_bridge_destroy own a store boot-
//     strapped from the shared local snapshot (single active bridge, v1);
//   - reads/writes cross as UTF-8 JSON bytes — schema evolution stays inside
//     Swift, the C signature never changes again;
//   - opc_bridge_last_error surfaces refusals verbatim;
//   - every returned buffer is freed via opc_bridge_free (malloc allocator
//     — Dart's malloc.free works directly).
//
// Why JSON not per-field accessors: the FFI contract must stay frozen while
// the data model evolves (it already has, 7 schema versions).
//
// THREADING (v1.1): callable from ANY host thread — each entry hops to the
// main queue when needed (onMain below), so the @MainActor store is touched
// exactly one call at a time. The first real host (Dart VM FFI, smoke #1)
// proved why: its "main" isolate thread is NOT the Swift MainActor executor,
// and a strict assumeIsolated contract trapped immediately. One constraint
// remains: do not call from a main-thread block that keeps the main queue
// busy (classic FFI deadlock hygiene; Flutter platform-thread calls are fine).
// ═══════════════════════════════════════════════════════════════════════

/// Bridge-owned mutable state. The NSLock makes every field access safe
/// against re-entrant sequencing; @MainActor assumeIsolated below puts all
/// store work on the contract thread. Two independent guarantees, one box.
final class OPCBridgeBox: @unchecked Sendable {
    let lock = NSLock()
    var store: CompanyStore?
    var lastError: String = ""
}

private let bridgeBox = OPCBridgeBox()

private func withBridgeLock<T>(_ body: (OPCBridgeBox) -> T) -> T {
    bridgeBox.lock.lock()
    defer { bridgeBox.lock.unlock() }
    return body(bridgeBox)
}

/// Run @MainActor store work from any host thread: assume in place when we
/// are already on main; otherwise hop via main-queue sync (the blocked
/// caller frees the main thread to service it). Darwin MainActor == main
/// queue, so both paths satisfy the isolation check legitimately.
private func onMain<T: Sendable>(_ work: @MainActor () -> T) -> T {
    if Thread.isMainThread {
        return MainActor.assumeIsolated(work)
    }
    var result: T?
    DispatchQueue.main.sync { result = work() }
    return result!
}

/// Bootstrap the store from the shared local snapshot (same file the GUI
/// and CLI read). Returns 0 on success; -1 when a bridge already exists.
@_cdecl("opc_bridge_create")
public func opc_bridge_create() -> Int32 {
    onMain {
        withBridgeLock { box in
            guard box.store == nil else {
                box.lastError = "bridge already created — call opc_bridge_destroy first"
                return -1
            }
            // liveChatEnabled:false — least privilege for this entry point:
            // the bridge's verbs never send employee chats, and a shell must
            // not inherit the GUI's default-on live-backend behavior by
            // accident (bootstrap's default == loadPersisted!).
            box.store = CompanyStore.bootstrap(loadPersisted: true, liveChatEnabled: false)
            return 0
        }
    }
}

/// Drop the store (idempotent; returned buffers are unaffected until freed).
@_cdecl("opc_bridge_destroy")
public func opc_bridge_destroy() {
    withBridgeLock { $0.store = nil }
}

/// Verbatim reason of the last refusal; "" when the last call succeeded.
/// Free the result with opc_bridge_free.
@_cdecl("opc_bridge_last_error")
public func opc_bridge_last_error() -> UnsafeMutablePointer<CChar>? {
    // Sendables (String) cross the isolation boundary; raw pointers never do
    // — the malloc copy happens OUTSIDE, in nonisolated code (bridgeDup).
    let message = withBridgeLock { $0.lastError }
    return bridgeDup(message)
}

/// Full company snapshot as UTF-8 JSON (schema == company-state.json,
/// carries schemaVersion). NULL when no bridge or encoding failed.
/// Free the result with opc_bridge_free.
@_cdecl("opc_bridge_snapshot_json")
public func opc_bridge_snapshot_json() -> UnsafeMutablePointer<CChar>? {
    let json: String? = onMain {
        withBridgeLock { box in
            guard let store = box.store else { return nil }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(store.currentSnapshot()) else { return nil }
            return String(decoding: data, as: UTF8.self)
        }
    }
    return json.flatMap { bridgeDup($0) }
}

/// Execute a boss-level command. Payload JSON contract (see opc_bridge.h):
///   goal {"text"} | advance {} | decide {"approvalID","approved"} | save {}
/// Write verbs honor the core's cross-process writer guard
/// (OPC_ALLOW_CONCURRENT_WRITE=1 override). Unknown verbs return -1 —
/// never a silent no-op: that is how shells and cores drift apart.
/// Returns 0 on success, -1 on refusal (then read opc_bridge_last_error).
@_cdecl("opc_bridge_command")
public func opc_bridge_command(_ verb: UnsafePointer<CChar>?,
                               _ payloadJSON: UnsafePointer<CChar>?) -> Int32 {
    // Decode the caller's C strings to Sendable values BEFORE hopping into
    // the isolated store work — raw pointers never cross the boundary
    // (Swift 6 #SendingRisksDataRace). Safe here: the host owns these
    // buffers for the duration of this synchronous call.
    let verbString = verb.map { String(cString: $0) }
    let payloadText = payloadJSON.map { String(cString: $0) }
    return onMain {
        withBridgeLock { box in
            guard let store = box.store, let verbString else {
                box.lastError = "bridge not created"
                return -1
            }
            let payload: [String: Any] = {
                guard let payloadText,
                      let data = payloadText.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data)
                        as? [String: Any] else { return [:] }
                return obj
            }()
            do {
                switch verbString {
                case "goal":
                    let text = (payload["text"] as? String) ?? ""
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw OPCBridgeRefusal(message: "goal text is empty")
                    }
                    try OPCWriteGuard.ensureExclusiveAccess()
                    if store.startCTOSupervisorGoal(goal: text) != nil {
                        store.saveSnapshot()
                    }
                case "advance":
                    try OPCWriteGuard.ensureExclusiveAccess()
                    _ = store.advanceCTOSupervisorLoop()
                    store.saveSnapshot()
                case "decide":
                    try OPCWriteGuard.ensureExclusiveAccess()
                    guard let idString = payload["approvalID"] as? String,
                          let approvalID = UUID(uuidString: idString) else {
                        throw OPCBridgeRefusal(message: "decide requires a UUID approvalID")
                    }
                    store.decideApproval(approvalID,
                                         approved: (payload["approved"] as? Bool) ?? false)
                    store.saveSnapshot()
                case "save":
                    try OPCWriteGuard.ensureExclusiveAccess()
                    store.saveSnapshot()
                default:
                    throw OPCBridgeRefusal(message: "unknown bridge verb '\(verbString)'")
                }
                box.lastError = ""
                return 0
            } catch let refusal as OPCBridgeRefusal {
                box.lastError = refusal.message
                return -1
            } catch let writer as OPCConcurrentWriterError {
                box.lastError = writer.message
                return -1
            } catch {
                box.lastError = String(describing: error)
                return -1
            }
        }
    }
}

public struct OPCBridgeRefusal: Error { let message: String }

/// strdup-shaped copy from the C allocator, so hosts free() / malloc.free()
/// it without allocator mismatch (Swift .allocate on Windows is
/// _aligned_malloc-backed — mixing those is heap corruption).
private nonisolated func bridgeDup(_ string: String) -> UnsafeMutablePointer<CChar>? {
    let bytes = Array(string.utf8)
    // Darwin/Glibc/WinSDK import malloc as UnsafeMutableRawPointer! (IUO) —
    // binding it checks the actual NULL (OOM) without platform branches.
    guard let raw = malloc(bytes.count + 1) else { return nil }
    bytes.withUnsafeBytes { src in
        raw.copyMemory(from: src.baseAddress!, byteCount: bytes.count)
    }
    raw.assumingMemoryBound(to: CChar.self)[bytes.count] = 0
    return raw.assumingMemoryBound(to: CChar.self)
}

/// Release any buffer this API returned (NULL tolerated; pairs with malloc).
@_cdecl("opc_bridge_free")
public func opc_bridge_free(_ ptr: UnsafeMutableRawPointer?) {
    free(ptr)
}
