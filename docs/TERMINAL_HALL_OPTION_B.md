# Terminal Hall, Option B — real interactive seats in the Flutter shell

Design sketch for the last pillar of issue #70: giving the Windows
(and macOS) Flutter shell genuine **interactive** employee terminals,
not just the read-only transcript mirror that option A v1 shipped
(bridge v1.2 `terminal_digest` + `terminal_tail`).

Status: **design wanted → proposed here**. Nothing in this document is
implemented yet; the numbers it cites are from the shipped code.

## What already exists (and why it matters)

The company already runs agents **without a terminal emulator**: the
macOS app spawns each agent as a one-shot `Process` with plain stdio
pipes (`CLIAgentRunner`), captures the stream into per-seat logs
(`productTerminalLogs`), and every surface — GUI, CLI, bridge, shell —
reads the same bytes through the frozen bridge. The transcript mirror
proved the read path is fully portable: no PTY required to SHOW work.

So Option B decomposes into exactly two gaps:

1. **INPUT**: the shell cannot inject a line into a running seat.
2. **LIFECYCLE**: on Windows there is no long-lived seat process at
   all — the current Windows shell mirrors logs of sessions the
   macOS app ran.

## Proposed transport: pipes over the bridge, not a PTY

**Recommendation: stay PTY-free.** Interactive seats via ConPTY (or
`openpty` on macOS) would give real TTYs, but they buy problems this
product does not have: terminal-emulation state, resize protocols, and
a Windows-only API surface that the six-symbol ABI would have to hide.
The company's agents are already run pipe-mode (they print progress,
they exit) — the one interactive flow that matters is the human
steering a long-running seat, and a line-based channel covers it.

### New bridge surface (contract v1.11, ABI still frozen at six symbols)

```
"terminal_send" {"agentID": "<uuid>", "line": "<text>"}
  rc=0  → the line was queued to the seat's stdin (or refused with a
          reason in last_error: no such seat, seat not interactive,
          product mismatch)
  rc=-1 → refusal, reason in last_error
```

Core side: `CompanyStore.terminalSend(agentID:, line:)` — writes to the
seat's stdin handle if the seat belongs to this process, otherwise
refuses with `seat not on this machine` (a shell on Windows speaking to
a core whose seats live on macOS gets an honest refusal, not a fake
ack). The line is ALSO appended to the seat's log (prefixed), so the
transcript stays the single narrative of the session — boss input is
part of the story, not a side channel.

### Shell side: xterm.js in a WebView, fed by `terminal_tail`

- The seat view becomes a WebView running xterm.js in **read-mostly
  mode**: it renders the byte stream that `terminal_tail` already
  serves, using the same cursor protocol (`nextOffset`) the transcript
  uses today. No new transport — the cursor math is proven (v1.2:
  never splits UTF-8, always advances).
- The input box calls `terminal_send`. One line at a time; no
  full-emulation round-trip.
- Colors/ANSI: xterm.js decodes the agent's ANSI escapes for free; the
  plain-text transcript mirror keeps working unchanged for surfaces
  that do not need them.

### Windows lifecycle: the shell owns its seats

The Windows shell can run agents natively — the core already builds
and runs there (`opc.exe` since v0.2.1, `CLIAgentRunner` is
Foundation-only). The missing piece is seat registry parity: the GUI
persisting which seats IT spawned, so a shell spawned on Windows lists
its own seats instead of mirroring nothing. `CLIAgentRunner` gains a
"spawn + keep stdin open" mode (today's one-shot is "spawn, wait,
collect"), and the seat registry rides the snapshot's existing
per-seat keys.

## Why not the alternatives

- **ConPTY end-to-end**: real TTYs, but the emulation complexity lands
  in both the bridge (win32 API calls) and the shell (full xterm
  handshake) while the product's agents run fine pipe-mode. Revisit if
  an agent genuinely requires a TTY (rare; most CLIs detect non-TTY and
  adapt).
- **Long-poll stream verb** (`stream_messages` callback): the cursor
  pull (`terminal_tail`) is already incremental, event-driven in the
  shell, and byte-cursor-stable — a push channel would duplicate it.
- **Full PTY multiplexer inside the core**: drags a terminal emulator
  into a portable core; the core's discipline (pure doors, frozen ABI)
  is the product's moat.

## Sequencing (each shippable alone)

1. **SHIPPED v0.17.0: `terminal_send`** (contract v1.11) — steer a
   live tmux seat. **Completed v0.18.0**: the surfaces — `opc tell`
   and the shell's steering input.
2. **SHIPPED v2.0.0: Windows seat spawning** (contract v1.12) —
   `OPCLocalSeatProcess` (keep-stdin, lives in the process seam file),
   `CLIAgentCommandBuilder.interactiveCommand` (codex honestly refused:
   its TUI needs a real TTY), the store's `spawnLocalSeat`/`stopLocalSeat`
   doors, and the shell's start/stop toggle. Seat output streams into
   the SAME per-seat transcript keys tmux seats write, so every read
   surface works unchanged; `terminal_send` falls back to the local
   seat — one verb, whichever office.
   Deliberately NOT a CLI verb: pipe seats belong to a long-lived
   office (the shell/bridge process). A `opc seat` verb would orphan
   the process and lose the transcript when the CLI exits — dishonest
   capability, so it does not exist.
3. **xterm.js rendering** (cosmetic polish — colors; the read path
   already works without it).
