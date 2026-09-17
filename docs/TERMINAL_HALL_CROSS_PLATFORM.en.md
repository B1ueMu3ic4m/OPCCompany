# Cross-Platform Terminal Hall: Proposal and As-Built (#70)

Status: **option A v1 shipped** (PR #77 bridge verbs + shell surface;
PR #78 snapshot slimming) · 2026-09-16 · Companion to
[WINDOWS_PORT_RFC.md](WINDOWS_PORT_RFC.md) (M3's 🟡 remainder is exactly this).
Continues [TERMINAL_HALL_DESIGN.en.md](TERMINAL_HALL_DESIGN.en.md) (the macOS
design as built); the Chinese original is
[TERMINAL_HALL_CROSS_PLATFORM.md](TERMINAL_HALL_CROSS_PLATFORM.md).

## What the hall actually is today (measured, not assumed)

The macOS hall is **not a terminal emulator**. The pipeline is:

1. agents run as **one-shot print-mode processes** (`claude -p …`, `codex exec …`,
   `gemini -p …`) — the prompt is a single argv, output streams back through
   `Process` **pipes** (no PTY anywhere in `OPCCompanyCore`; the #9 launch seam
   kept pipes);
2. every stdout/stderr chunk → `appendTerminalLog` → `productTerminalLogs:
   [String: String]` (key = `productUUID:agentUUID`), plain text,
   `@Published`, **already part of the persisted snapshot**. The legacy
   `terminalLogs: [UUID: String]` mirror field survives for schema
   compatibility but — since PR #78 — no longer double-grows: migration is
   now loss-free pruning, and divergent text is kept on BOTH sides;
3. the bridge's `opc_bridge_snapshot_json` encodes `currentSnapshot()` →
   **the shell already receives terminal transcripts today** (inside the same
   payload the boss board renders from);
4. the only "interactive" path that exists (`persistentProtocol`) is tmux-based
   (`send-keys` + `capture-pane` polling) — tmux does not resolve on Windows, so
   that capability already degrades to one-shot there by design (see the #9 record).

So "employee seats running on Windows" is 90% shipped: execution already runs
(one-shot, through the seam, `.cmd` shims included) and output already lands in
the snapshot. What's missing is **a good viewing surface in the shell**, not a
transport miracle.

## Options

### A. Transcript mirror (v1 shipped — PRs #77/#78)
The shell renders per-agent transcripts directly: tap an employee chip →
monospace `SelectableText` panel at the bottom, auto-follow the tail,
scroll-up pauses follow (`flutter_shell/lib/main.dart`). Zero native code,
zero new plugins. Fetching is incremental: the shell pulls the digest,
compares cursors, and only requests byte windows that grew; a log that
SHRANKS (cleared/truncated) resets that agent's panel; switching product
invalidates the whole cache.

The two bridge verbs that shipped (6-symbol C ABI stayed frozen; queries
return rc=0 with the JSON payload riding `opc_bridge_last_error`):
- `terminal_digest {}` → `{agentID: byteLength}` for the selected product,
  prefix-filtered so a cross-product leak is structurally impossible;
- `terminal_tail {agentID, afterOffset, maxBytes}` → `{text, nextOffset,
  length}` via the pure helper `OPCBridgeWindow.read` (never splits a
  UTF-8 codepoint, cursor always advances, out-of-range offsets clamp,
  a cursor inside a codepoint rewinds to its start).

Updates are event-driven (digest after each verb); the originally sketched
`stream_tick` probe / `logRevision` counter turned out unnecessary — the
digest itself is the liveness signal. Periodic polling is deferred to M5.

Honesty property: what you see is exactly what the macOS non-tmux path shows —
no second-class experience claim, it's the SAME experience.

### B. xterm.js in a WebView + native PTY
Real emulation: TUIs, colors, interactive REPLs, resize. Cost: a desktop
WebView plugin (xterm needs `webview_windows` / macOS `WKWebView` bridging —
new supply chain + plugin registration), a PTY layer the core never had
(`forkpty`/ConPTY), and an escape-sequence source: one-shot print mode emits
mostly plain text anyway — **B mostly serves interactive mode, which the core
does not run today except via macOS-only tmux**. Deferred to M5 unless a
maintainer wants to own it; B does NOT unblock Windows.

### C. A now, B later behind the same verb surface
The `terminal_tail` contract doesn't change if a PTY arrives later; the shell
UI can swap the renderer without a bridge ABI break (verbs are additive).

## Recommendation
**C** — shipped as such: A landed as v1 of the Windows-visible hall
(PR #77/#78); B stays an M5 option gated on a real interactive-mode need
(which is itself a product question: `-p` print agents have no stdin story
on ANY platform).

## Status of the concrete asks (as of PR #78)
1. ~~`terminal_tail` verb + revision counter in the bridge~~ — **DONE
   (PR #77)**: `terminal_digest` + `terminal_tail` live in `OPCBridge.swift`'s
   `command` dispatch; the window math is a pure helper
   (`OPCBridgeWindow.read`) pinned by behavior tests. The revision counter
   was not needed — the digest doubles as the liveness signal.
2. ~~Flutter render~~ — **DONE (PR #77)**: employee chips → bottom
   transcript panel with follow-bottom + scroll-up-pause in
   `flutter_shell/lib/main.dart`; widget tests drive the real FFI seam
   through `FakeOpcBridge` (malloc'd strings tracked by address, every one
   asserted freed).
3. ~~Snapshot digesting~~ —— **DONE (PR #78, issue #70 task 3)**: the
   double-write stopped; the legacy `terminalLogs` field stays in the schema
   (never deleted) and migration became loss-free pruning at load (exact
   duplicates and emptied entries drop, divergent text is kept on BOTH
   sides). The more aggressive idea — moving logs out of the full-snapshot
   payload entirely — was NOT adopted: measured, the macOS hall reads
   in-memory state through `terminalLogForCurrentProduct` and the snapshot
   remains the cross-process sync channel, so removal would break existing
   consumers while the pruning already reclaimed the duplicated bytes.

Still open (claim by replying):
- **Boss-hall wiring**: transcript entry points on the employee seats in
  the macOS SpriteKit scene (separate from the Flutter shell).
- **Periodic polling** (M5): updates are event-driven today, so a log that
  grows outside a bridge call is not noticed until the next event.
- **Option B**: xterm.js + native PTY/ConPTY, gated on interactive mode
  becoming a real product question.

Comments welcome; claim by replying. Merged contributions get release-notes
credit (see CONTRIBUTING.md).
