# The doors — one math, every surface

The product's core discipline: every answer the boss can ask for is a
**door** — a pure read computed live by the store at question time,
surfaced on every front end through the SAME math, so no two surfaces
can ever disagree. Nothing a door reports is ever stored as a verdict
(a stored liveness freezes a live one), `now` is injectable so tests
pin time instead of racing it, and repeat reads are byte-stable.

The authoritative wire contract is [`include/opc_bridge.h`](../include/opc_bridge.h);
a docs-drift guard test (`OPCBridgeVerbDocTests`) demands exact
equality between the verbs documented there and the verbs the bridge
handles — both directions.

## Read doors

| Door | Store math | Bridge verb | Since | CLI | macOS GUI | Shell |
|---|---|---|---|---|---|---|
| Approvals queue | pending queue serializer | `approvals_list` | v1.3 | `opc approvals` | ✓ popover | ✓ card |
| Decision ledger | resolved approvals | `history_list` | v1.4 | `opc history` | ✓ | ✓ |
| Delivery shelf | artifacts + existence at read time | `deliverables_list` | v1.5 | `opc deliverables` | ✓ | ✓ |
| Morning standup | `standupWindow()` | `standup_window` | v1.6 | `opc standup` | ✓ headline | ✓ card |
| Team window | `teamWindow()` | `team_stats_list` | v1.7 | `opc team` | ✓ panel | ✓ panel |
| Stall watch | `stallWatch()` | `stalls_list` | v1.8 | `opc stalls` | ✓ panel | ✓ panel |
| Catch-up page | `catchUpPage()` | `catchup_md` | v1.9 | `opc catchup` | ✓ | ✓ card |
| Weight | `snapshotWeightReport()` | `weight_json` | v1.10 | `opc weight` | ✓ panel | ✓ card |
| Transcripts | per-seat log keys + byte cursor | `terminal_digest` / `terminal_tail` | v1.1/v1.2 | `opc watch` | ✓ hall | ✓ hall |
| Visible transcript | `visibleTerminalLog()` (product-scoped, sanitized, compacted) | `transcript` | v1.14 | `opc transcript` | ✓ hall card | ✓ visible/raw toggle |
| Agent desk | profile chips + session + assigned tasks + work queue + inbox accessors | `desk` | v1.17 | `opc desk` | ✓ agent desk | — |
| Open windows | `openTerminalWindowAgentIDs()` (one `tmux list-windows` probe) | — (store read, v2.5.0) | — | `opc watch` seats line · `opc hall` | ✓ hall chip (throttled, v2.11.0) | — |
| Snapshot | `snapshotJSONData()` | `opc_bridge_snapshot_json` | v1.0 | `opc status --json` | ✓ | ✓ |

## Write doors

| Door | Store math | Bridge verb | Since | CLI | macOS GUI | Shell |
|---|---|---|---|---|---|---|
| Goal | goal chain | `goal` | v1.0 | `opc goal` | ✓ | ✓ |
| Advance | supervisor step | `advance` | v1.0 | `opc advance` | ✓ | ✓ |
| Decide | `decideApprovalChecked` | `decide` | v1.0 | `opc decide` | ✓ popover | ✓ |
| Product select | product switch | `product_select` | v1.0 | `opc use` | ✓ sidebar | ✓ |
| Save | snapshot persist | `save` | v1.0 | (every write) | ✓ | ✓ |
| Autopilot dispatch | `runCTOAutopilot()` | `autopilot` | v1.15 | `opc autopilot` (cycles + honest stops) | ✓ button | ✓ button |
| Checkpoint | `createSafetyCheckpointChecked(reason:)` | `checkpoint` | v1.16 | `opc checkpoint <reason>` | ✓ (auto before risky ops) | ✓ field + button |
| **Steering** | `terminalSendLine` | `terminal_send` | v1.11 | `opc tell` (+ `-` stdin, v2.4.0) | ✓ send line (v2.1.0) | ✓ input (v0.18) |
| Seat spawn/stop | `spawnLocalSeat`/`stopLocalSeat` | `seat_spawn` / `seat_stop` | v1.12 | — (deliberate: pipe seats belong to a long-lived office) | — (tmux seats are the macOS shape) | ✓ toggle (v2.0.0) |
| Seat roster | `localSeatStatuses()` | `seat_list` | v1.13 | — (a visitor sees no seats) | — | ✓ drives the toggle (v2.3.0) |

## The honest-refusal discipline

Every door and write answers with its reason, verbatim, on the
refusal channel — never a fake ack, never a guessed toggle. A CLI
visitor never sees another process's local seats; a shell never
claims a seat it cannot see; the doctor (`opc hall`, v2.4.0) reports
physically-open tmux windows, deliberately distinct from
"could a send go through right now".

## Why the CLI cannot start seats

Pipe seats are facts of the office process that spawned them. A
`opc seat` verb would orphan the process and lose the transcript when
the CLI exits — dishonest capability, so it does not exist. tmux
seats are different: the session lives in the tmux SERVER, which is
why `opc tell` can steer them from any process on the machine.
