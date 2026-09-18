/* opc_bridge.h — stable C ABI of the OPC Company portable core.
 *
 * The single source of truth for symbols is OPCBridge.swift (@_cdecl names);
 * this header mirrors it for C/C++/Zig consumers and ships with the
 * OPCCompanyBridge dynamic library. Dart: use dart:ffi with these typedefs,
 * and free returned pointers with malloc.free (allocator pairs by contract).
 *
 * Threading (v1.2): safe to call from ANY host thread — the bridge hops to
 * the main queue internally, which REQUIRES the host's main thread to keep
 * servicing its queue while a worker call is in flight (every GUI does; a
 * thread blocked in a sync wait does not — worker-thread calls then
 * deadlock by design, pinned empirically by OPCBridgeThreadStormTests).
 * Avoid calling from a main-thread block that
 * never drains (classic FFI deadlock hygiene).
 */
#ifndef OPC_BRIDGE_H
#define OPC_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

/* Bootstrap the store from the shared local snapshot.
 * Returns 0 on success, -1 if already created (see opc_bridge_last_error). */
int32_t opc_bridge_create(void);

/* Drop the store handle (memory stays owned by Swift; idempotent). */
void opc_bridge_destroy(void);

/* Verbatim reason of the last refusal. Free with opc_bridge_free. */
char *opc_bridge_last_error(void);

/* Full company snapshot as UTF-8 JSON (schema == company-state.json,
 * includes schemaVersion). Returns NULL on OOM. Free with opc_bridge_free. */
char *opc_bridge_snapshot_json(void);

/* Execute a boss-level command. payload_json is a UTF-8 JSON object:
 *   "goal"    {"text": "..."}
 *   "advance" {}
 *   "decide"  {"approvalID": "<uuid>", "approved": true}
 *       Unknown IDs and already-decided approvals return -1 with a reason
 *       (the bare store call is a silent no-op for both — a double-tap or
 *       a stale approval list must never read as success).
 *   "save"    {}
 *   "product_select" {"productID": "<uuid>"}
 *       Switches the selected product through the same store path the
 *       SwiftUI sidebar uses (agent team restart + save). Unknown IDs
 *       return -1 with a reason: the bare store call is a silent no-op,
 *       and a shell must never mistake one for a switch.
 * Query verbs (#70 option A — transcripts are pulled, not pushed; the full
 * snapshot already carries logs, these verbs exist to avoid re-fetching it
 * on a poll loop):
 *   "terminal_digest" {}
 *       rc=0; the RESULT rides opc_bridge_last_error as a JSON object
 *       {"<agentID>": byteLength, ...} of the selected product's agent
 *       logs (keys are the storage key's agentID suffix — what roster
 *       rows index by; the product scope is implicit and filter-locked).
 *   "terminal_tail" {"agentID": "<uuid>", "afterOffset": 0, "maxBytes": 16384}
 *       rc=0; the RESULT rides opc_bridge_last_error as JSON
 *       {"text": "...", "nextOffset": N, "length": L}. nextOffset is
 *       character-aligned (a window never splits a UTF-8 glyph; tiny
 *       maxBytes may overshoot by at most 3 bytes to guarantee progress).
 *       afterOffset is clamped to [0,L]; an interior-codepoint offset is
 *       rewound to that codepoint's start. Resume with nextOffset for exact
 *       concatenation. A length-only digest detects growth/shrink, not a
 *       same-length replacement; full snapshots still include the logs.
 *   "approvals_list" {}            (v1.3)
 *       rc=0; the RESULT rides opc_bridge_last_error as a JSON array
 *       [{"id":"<uuid>","title":"...","reason":"...",
 *         "requesterID":"<uuid>"?}, ...] — the pending approvals of the
 *       CURRENT product (product scope filter-locked inside the store,
 *       cross-product leak structurally impossible). requesterID is the
 *       raising agent; absent when the core recorded no requester.
 *       Read-only: never mutates, never touches the writer guard.
 * IMPORTANT: for query verbs, success means rc==0 AND last_error holds the
 * payload — branch on rc, never on whether last_error is empty. The ABI is
 * frozen at six symbols; a query result channel is a contract choice, not a
 * symbol change.
 * Unknown verbs return -1 (never a silent no-op). Write verbs honor the
 * core's cross-process writer guard (OPC_ALLOW_CONCURRENT_WRITE=1 overrides).
 * Returns 0 on success, -1 on refusal — read opc_bridge_last_error. */
int32_t opc_bridge_command(const char *verb, const char *payload_json);

/* Release any buffer returned by this API (NULL tolerated). */
void opc_bridge_free(void *ptr);

#ifdef __cplusplus
}
#endif

#endif /* OPC_BRIDGE_H */
