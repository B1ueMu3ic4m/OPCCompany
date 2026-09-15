# Windows Port RFC

Status: **Route A = SHIPPED** (bridge + Flutter shell live since v0.3.0,
2026-09-14) · Started: 2026-09-07 · Owner: @B1ueMu3ic4m
Progress log: [WINDOWS_COMPILE_REPORT.md](WINDOWS_COMPILE_REPORT.md)

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
M0  Platform-abstraction refactor (on macOS, no-regret)      ✅ CLOSED 2026-09-12
     ├─ SecretStore protocol + OPCAppPaths                    ✅ PR #7
     ├─ ProcessRunner wrapper (path/arg quoting on Windows)   ← open, #9
     ├─ i18n: replace Bundle.main swizzle with a portable lookup ← open, #10
     └─ Split core into OPCCompanyCore (no UI) + OPCCompanyUI (SwiftUI) ✅
        (shim chain proven layer-by-layer on real Windows CI:
         CryptoKit 60→0 · SwiftUI observation 76→0 · SQLite vendored 62→0 ·
         Security→DPAPI 62→0 · ObjC swizzle gated 62→0 · cross-layer 420→0)

M1  Windows compile spike                                      ✅ CLOSED (automated)
     spike #6: logic package builds with ZERO errors (496/496 jobs);
     spike #9: DPAPI live 4-step probe green. The one-off guide became
     standing CI (windows.yml + windows-shell.yml run on every push).

M2  Route decision from M1 data:                               ✅ A = GO, executed
     ├─ A) Swift core reused via FFI + Flutter UI  ← SHIPPED: OPCBridge
     │                                                (6 C symbols) + flutter_shell
     ├─ B) Full Flutter port — not needed; A's census was 2 modules, both
     │    with official replacements (swift-crypto, observation shim)
     └─ C) Community-driven — still open for #9 / #10 (good-first-issue)
```

Routes A and B are **not** mutually exclusive over time: B's Dart core can
later back a SwiftUI macOS rewrite too, converging on one cross-platform stack.

## What we're NOT doing

- No Electron/Tauri rewrite of the existing macOS app — the Mac build stays native.
- No half-broken "works under Wine" claims.
- No promise on dates until M1 data exists.

## Asking for help (still open)

The core compiles and the shell runs on Windows — but parity work remains.
If you have shipped Swift-on-Windows or Flutter-desktop projects:

- **#9 ProcessRunner** — the one abstraction M0 deferred: CLI agents launch
  via `Process` in ~8 places; Windows needs `.cmd` resolution + quoting.
- **#10 portable i18n** — replace the ObjC bundle swizzle with a protocol.
- **Windows terminal hall** — the shell today is boss-operations only
  (goal/board/approvals); employee terminal seats need a cross-platform
  story (xterm.js embed is the candidate). Design discussion welcome.

We credit every merged contribution in release notes and the changelog.

## Milestones

| Milestone | Deliverable | Exit criteria | Status |
|---|---|---|---|
| M0 | Abstraction layer | 578+ tests green on macOS; core/UI split builds | ✅ closed (shim chain CI-proven layer by layer) |
| M1 | Compile spike | Error census published in this repo | ✅ closed — census in WINDOWS_COMPILE_REPORT.md; spike became standing CI |
| M2 | Route decision | A/B/C chosen with data, recorded here | ✅ Route A, executed |
| M3 | MVP | Boss→CTO→employee→terminal loop runs on Windows | 🟡 **partially** — boss→CTO loop verified on Windows CI (goal→task chain→advance→save, 10/10 smoke); employee *terminal seats* are still macOS-GUI-only (see #9 + terminal-hall discussion) |
| M4 | Parity + distribution | Test suite ported; winget/MSIX install | 🔭 open — tests run on Windows CI for the logic package (compile); behavioral suite port + signing/MSIX next |
