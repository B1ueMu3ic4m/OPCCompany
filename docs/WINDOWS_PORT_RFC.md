# Windows Port RFC

Status: **Proposed** · Started: 2026-09-07 · Owner: @B1ueMu3ic4m

## Why

OPC Company today is macOS-only (SwiftUI + SpriteKit). The AI coding agents it
orchestrates — Claude Code, Codex CLI, Gemini CLI — all ship first-class
Windows support, and the Windows developer install base is at least as large
as macOS. A Windows build is the single highest-leverage expansion of the
audience.

## Current platform coupling (measured, not guessed)

Core layer (`Sources/OPCCompanyCore`) import census:

| Framework | Files | Windows availability |
|---|---|---|
| Foundation | 28 | ✅ (swift-corelibs-foundation) |
| SwiftUI | 13 | ❌ (Apple-only) |
| SQLite3 | 6 | ✅ (system lib / bundled) |
| SpriteKit | 2 | ❌ (Apple-only) |
| AppKit | 2 | ❌ (Apple-only) |
| Security (Keychain) | 1 | ❌ → replaced by DPAPI/file store |
| CryptoKit | 1 | ❌ → swift-crypto fallback |
| ObjectiveC | 1 | ❌ (bundle-swizzle i18n hack — Windows needs a different mechanism) |

Good news from the M0 abstraction work:
- **No PTY dependency** — terminal sessions use `Process` pipes, which work on Windows.
- **Persistence is portable** — JSON snapshot + SQLite, both cross-platform.
- **Secret storage is isolated** — `Security` is confined to one file behind
  `OPCSecretStoreProtocol` (guard-tested).
- **Paths are isolated** — `OPCAppPaths` resolves `%APPDATA%` vs Application Support.

The hard part is UI: ~12k lines of SwiftUI + ~2k lines of SpriteKit have no
Windows target.

## Decision tree (data-driven, not faith-based)

```
M0  Platform-abstraction refactor (on macOS, no-regret)      ← IN PROGRESS
     ├─ SecretStore protocol + OPCAppPaths                    ✅ PR #7
     ├─ ProcessRunner wrapper (path/arg quoting on Windows)
     ├─ i18n: replace Bundle.main swizzle with a portable lookup
     └─ Split core into OPCCompanyCore (no UI) + OPCCompanyUI (SwiftUI)

M1  Windows compile spike (on a real Windows box)            ← GUIDE READY
     Build OPCCompanyCore with the Swift Windows toolchain;
     collect the error census.

M2  Route decision from M1 data:
     ├─ A) Swift core reused via FFI + Flutter UI   — only if core compiles
     │                                                with < ~20 blocking errors
     ├─ B) Full Flutter port (logic rewritten in Dart,
     │    578 tests re-expressed as the acceptance spec) — default if A is painful
     └─ C) Community-driven port — RFC + good-first-issues below; if a
          contributor picks it up, cost to us ≈ 0
```

Routes A and B are **not** mutually exclusive over time: B's Dart core can
later back a SwiftUI macOS rewrite too, converging on one cross-platform stack.

## What we're NOT doing

- No Electron/Tauri rewrite of the existing macOS app — the Mac build stays native.
- No half-broken "works under Wine" claims.
- No promise on dates until M1 data exists.

## Asking for help (route C)

If you have shipped a Swift-on-Windows or Flutter-desktop project:

- **Review this RFC** — comment on the decision tree; what did we miss?
- **Run the M1 spike** on your Windows machine and post the error census
  (`docs/WINDOWS_SPIKE_GUIDE.zh-CN.md`, English version coming).
- **Claim a good-first-issue** from the `windows-port` label.

We will credit every merged contribution in release notes and the changelog.

## Milestones (draft)

| Milestone | Deliverable | Exit criteria |
|---|---|---|
| M0 | Abstraction layer | 578+ tests green on macOS; core/UI split builds |
| M1 | Compile spike | Error census published in this repo |
| M2 | Route decision | A/B/C chosen with data, recorded here |
| M3 | MVP | Boss→CTO→employee→terminal loop runs on Windows |
| M4 | Parity + distribution | Test suite ported; winget/MSIX install |
