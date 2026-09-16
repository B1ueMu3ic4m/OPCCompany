/* opc_bridge.h — stable C ABI of the OPC Company portable core.
 *
 * The single source of truth for symbols is OPCBridge.swift (@_cdecl names);
 * this header mirrors it for C/C++/Zig consumers and ships with the
 * OPCCompanyBridge dynamic library. Dart: use dart:ffi with these typedefs,
 * and free returned pointers with malloc.free (allocator pairs by contract).
 *
 * Threading (v1.1): safe to call from ANY host thread — the bridge hops to
 * the main queue internally. Avoid calling from a main-thread block that
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
 *   "save"    {}
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
