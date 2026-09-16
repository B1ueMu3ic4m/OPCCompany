# Cross-Platform Terminal Hall Proposal (#70 · discussion wanted)

Status: **proposal, comments welcome** · 2026-09-16 · Companion to
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
2. every stdout/stderr chunk → `appendTerminalLog` → `terminalLogs: [UUID: String]`,
   plain text, `@Published`, **already part of the persisted snapshot**;
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

### A. Transcript mirror (recommended v1)
Render `terminalLogs` in the Flutter shell — one tab/row per agent,
auto-follow the tail, monospace `SelectableText`. Zero native code, zero new
plugins; the data is in every snapshot pull the shell already does.

Two small bridge verbs keep it from being janky:
- `terminal_tail {agentID, maxBytes, afterOffset}` → `{text, nextOffset}` at
  O(window) cost (no re-shipping megabyte logs on every snapshot refresh; the
  snapshot keeps only a `terminalLogSizes` digest);
- `stream_tick {since}` as a cheap liveness probe so the shell knows WHEN to
  pull tails (or: the existing Published changes can drive a `logRevision: Int`
  counter the shell diffs).

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
**C**: ship A as v1 of the Windows-visible hall (small, honest, reuses the
snapshot the shell already holds), keep B as an M5 option gated on a real
interactive-mode need (which is itself a product question: `-p` print agents
have no stdin story on ANY platform).

## Help wanted (concrete)
1. **`terminal_tail` verb + revision counter in the bridge** — ~100 lines
   Swift + 3 tests; start at `OPCBridge.swift`'s `command` dispatch (next to
   the `goal/advance/decide/save` handlers) + `CompanyStore+Runtime.swift`
   `appendTerminalLog` for the revision hook. Good-first-issue sized.
2. **Flutter render**: scrollable per-agent transcript with follow-bottom +
   manual-scroll-pause (classic log-viewer UX). `company_home_test.dart`
   shows the widget-test seam (FakeOpcBridge) — UI tests expected.
3. Opinions on the snapshot-digest idea (keep `terminalLogs` out of the
   full-snapshot payload and behind the tail verb? breaks the GUI? probably
   not — the GUI reads in-memory state, snapshot consumers are CLI/bridge —
   VERIFY before implementing, `opc report` reads transcript-adjacent fields).

Comments welcome; claim by replying. Merged contributions get release-notes
credit (see CONTRIBUTING.md).
