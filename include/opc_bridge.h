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
 *   "history_list" {}              (v1.4)
 *       rc=0; the RESULT rides opc_bridge_last_error as a JSON array
 *       [{"id":"<uuid>","title":"...","reason":"...","status":
 *         "approved"|"rejected","decidedAt":<epoch-seconds>?,
 *         "requesterID":"<uuid>"?}, ...] — the RESOLVED approvals of the
 *       CURRENT product, newest-first (decidedAt, createdAt as fallback,
 *       id as final tiebreak — the store's order, not a bridge guess),
 *       capped at 50 rows so one reply can never outrun the smuggle
 *       channel. decidedAt is absent only for pre-v0.6 legacy rows.
 *       Read-only, same guard silence as approvals_list.
 *   "deliverables_list" {}         (v1.5)
 *       rc=0; the RESULT rides opc_bridge_last_error as a JSON array
 *       [{"id":"<uuid>","title":"...","kind":"report|source|...",
 *         "path":"<claimed path>","existsNow":true|false,
 *         "taskID":"<uuid>"?,"createdAt":<epoch-seconds>}, ...] — the
 *       CURRENT product's delivery-view artifacts, newest-first (the
 *       store's order, not a bridge guess), capped at 50. The delivery
 *       view = what the boss's command center draws (maintenance records
 *       excluded), so shell and GUI never disagree about what counts.
 *       existsNow is computed AT READ TIME by the bridge — never stored,
 *       never frozen in the snapshot: delete a file and the very next
 *       call flips the row. Read-only, same guard silence as approvals_list.
 *   "standup_window" {}              (v1.6)
 *       rc=0; the RESULT rides opc_bridge_last_error as a JSON OBJECT
 *       (not array): {"hours":24,"newWork":N,"decisions":N,"deliveries":N,
 *       "missing":N,"risks":N,"awaitingNow":N} — one rolling window's
 *       TRAFFIC for the CURRENT product, computed live by the store's
 *       own standup door (events+approvals+artifacts; 'missing' is the
 *       window's deliveries that fail the existence door RIGHT NOW;
 *       'awaitingNow' is the live pending queue, NOT windowed). No
 *       parameters: the default 24h window is the whole contract.
 *       Since v0.13 the object serializes with .sortedKeys — repeat
 *       reads are byte-stable (it was the last channel with unstable
 *       key order).
 *       Read-only, same guard silence as approvals_list.
 *   "team_stats_list" {"hours":N}?   (v1.7)
 *       rc=0; the RESULT rides opc_bridge_last_error as a JSON ARRAY:
 *       [{"agentID":"<uuid>","name":"<display>","assigned":N,
 *       "deliveries":N,"missing":N,"asked":N,"risks":N,"activeNow":N}, ...]
 *       — per-employee TRAFFIC for the CURRENT product over the window
 *       (default 24h; "hours" is an optional positive int). Row order IS
 *       the contract: traffic-desc, and the unattributed row (no agentID
 *       key, name "未分配") LAST — it collects events with no agent,
 *       artifacts whose task chain dead-ends, orphan artifacts; attribution
 *       never fabricates an owner. "missing" rides the v0.7 existence door
 *       AT READ TIME. Read-only, same guard silence as approvals_list.
 *   "stalls_list" {"over_minutes":N}?  (v1.8)
 *       rc=0; the RESULT rides opc_bridge_last_error as a JSON ARRAY:
 *       [{"itemID":"<uuid>","name":"<display>","status":"<raw>",
 *       "dwellMinutes":N,"waitingOnYou":true|false, "agentID":"<uuid>"?},
 *       ...] — non-terminal work parked LONGER than N minutes
 *       (default 30) on the current product, longest-frozen FIRST; the
 *       unattributed row (no agentID key when the roster lost the agent —
 *       name is then the localized unassigned label) sorts LAST.
 *       "waitingOnYou" is a status fact (the item waits on approval),
 *       never an accusation. dwell/threshold math runs INSIDE the store's
 *       door at read time — pure read, zero writes. Same guard silence
 *       as approvals_list.
 *   "catchup_md" {"hours":N,"over_minutes":N}?  (v1.9)
 *       rc=0; the RESULT rides opc_bridge_last_error as a plain UTF-8
 *       STRING (not JSON — the page IS the payload): the catch-up page
 *       for the CURRENT product, composed live by the store's own doors
 *       (standup_window, team_stats_list, stalls_list, the pending
 *       queue, the v0.7 existence door) — zero new math, so the shell's
 *       page can never drift from the CLI's. Section order IS the
 *       contract: traffic, who, stuck, desk, shelf, footer; a quiet
 *       section keeps its place with a quiet line (never omitted).
 *       No wall-clock inside: byte-stable for a given state, parameters
 *       and localization. "hours" (default 24, positive int) and
 *       "over_minutes" (default 30, non-negative int) are optional.
 *       Read-only, same guard silence as approvals_list.
 *   "terminal_send" {"agentID":"<uuid>","line":"<text>"}  (v1.11)
 *       rc=0 → the line was injected into the agent's LIVE tmux-backed
 *       seat (tmux pastes it atomically with the newline; the seat
 *       echoes it, so the transcript stays the single narrative).
 *       rc=-1 with a reason in last_error: not a UUID, no such agent,
 *       no live seat on this machine (a seat may live on another
 *       device, or the agent is not tmux-backed — never a fake ack),
 *       empty line, line > 4096 bytes, or a failed paste. Write ON THE
 *       SEAT, never on the snapshot; the writer guard does not apply
 *       (no company state changes). Since v1.12 a machine without a
 *       tmux seat falls back to the agent's LOCAL pipe seat (see
 *       seat_spawn) — one verb, whichever office you're in; the
 *       refusal wording stays v1.11-stable.
 *   "seat_spawn" {"agentID":"<uuid>"}    (v1.12)
 *       rc=0 → a LONG-LIVED local seat started for the agent: its CLI
 *       in interactive mode, stdin kept open (pipe-mode — no tmux, no
 *       ConPTY), output streaming into the SAME per-seat transcript
 *       keys tmux seats write, so terminal_digest/terminal_tail
 *       surfaces work unchanged. rc=-1 with a reason in last_error:
 *       not a UUID, no such agent, the employee is not a CLI (API/
 *       local), the backend is one-shot-only (codex's TUI needs a real
 *       TTY), the command is not installed, or the agent already has a
 *       live local seat. The registry is a RUNTIME fact — never
 *       persisted, never guessed across restarts.
 *   "seat_stop" {"agentID":"<uuid>"}     (v1.12)
 *       rc=0 → the agent's local seat was stopped (stdin EOF, then
 *       SIGINT → SIGTERM with a grace window). rc=-1: not a UUID or
 *       no local seat for this agent. Write on the PROCESS, never on
 *       the snapshot.
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
