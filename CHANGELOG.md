# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Windows DPAPI secret store (closes #11)**: `OPCDPAPISecretStore` —
  per-user `CryptProtectData` via a header-only `CWinDPAPI` shim (same
  pattern as CSQLite; crypt32 linked Windows-only). API keys now have a
  real at-rest protection story on Windows instead of the fail-closed
  stub: ciphertext blobs under `secrets/<uuid>.blob`, app-domain entropy
  for channel binding, `CRYPTPROTECT_UI_FORBIDDEN`, UUID-whitelisted paths.
  `OPCKeychainSecretStore` routes there automatically via typealias —
  zero call-site changes.
- Spike #7 gate: a real **runtime probe** (`spikeprobe`) executes
  save→load-match→ciphertext-on-disk→delete on the Windows runner —
  compiling DPAPI headers proves nothing; the step now fails unless all
  four probe lines are green.
- 1 guard test (path-injection/UI-forbidden/entropy/wiring invariants)
### Changed
- KeychainStore's `#else` branch: fail-closed remains ONLY where no DPAPI
  is reachable (Linux dev boxes); Windows gets the real store.

### Fixed
- **CLI data-loss guard (audit 2026-09-09)**: `opc goal`/`opc advance` now
  refuse to write while OPCCompany.app is running (pgrep, comm-name exact so
  the CLI never self-matches; sequential CLI runs stay safe) — previously a
  CLI save from stale-read state could silently rewind whatever the GUI
  persisted meanwhile. Override: `OPC_ALLOW_CONCURRENT_WRITE=1`
- Windows/Linux `OPCObservationBus` listener list is now token-addressable
  with `removeListener` (M3 FFI disconnects must be able to unsubscribe;
  the append-only list leaked every connected UI client)

### Added
- 3 audit regression tests: guard-signal invariants (no mtime, no
  in-process timestamp — anti-resurrection), bus add/remove semantics

## [0.2.0] - 2026-09-08

### Added
- **Headless CLI `opc` (v0.2.0)** — `status` / `goal` / `advance` / `report`
  drive the same CompanyStore and local snapshot as the GUI; links only the
  portable core (zero new dependencies, hand-rolled parser), guarded by 2
  source-scan tests (no UI-framework or direct-persistence imports allowed)
- Spike #6 (run 34215450265): **logic package builds on real Windows with
  ZERO errors** (496/496 jobs, 334 s) — M0 portability milestone closed; the
  83 remaining census errors are UI-layer files only (M3 Flutter scope)
- `docs/WINDOWS_COMPILE_REPORT.md`: M1 spike results — core layer compiles on
  Windows with only 2 blocking modules (CryptoKit → swift-crypto, SwiftUI
  observation → OpenCombine); RFC status updated to **Route A = GO**
- Spike #2 re-run section: both shims verified on real Windows (CryptoKit 60→0,
  SwiftUI observation 76→0); next blocker SQLite3 (62 errors, 6 files) filed
  as issue #42
- Vendored SQLite amalgamation 3.50.4 as the `CSQLite` C target (public
  domain; SHA256-tracked `Sources/CSQLite/VENDORED.txt`). The 6 SQLite-using
  logic files switch per-file between the system `SQLite3` module (Apple)
  and `CSQLite` (Windows); the dependency is Windows-only so the macOS
  build graph is untouched (578/578 tests green, closes issue #42)
- Spike #3 re-run: SQLite shim verified on real Windows (62→0); Security
  surfaced as the last logic blocker (62 errors, all `KeychainStore.swift`)
  — fixed by gating it behind `#if canImport(Security)` with a fail-closed
  Windows placeholder (no plaintext interim; saves raise a boss-visible
  risk event); spike #4 running for the zero-blocker confirmation
- Spike #4 re-run: Security shim verified on real Windows (62→0). Final
  logic-package blocker `ObjectiveC` (62 errors, all `L10nBundleOverride.swift`)
  — gated the Bundle swizzle behind `#if canImport(ObjectiveC)` with a
  same-API no-op recorder on Windows (dynamic strings unaffected; neutral
  replacement tracked as issue #10). Spike #5 = zero-blocker confirmation
- `SECURITY.md`: local-first design stance, per-surface protection table,
  private vulnerability reporting via GitHub Security Advisories
- README (en/zh): star CTA footer; Security section now links SECURITY.md
- **Windows port M0 (platform abstraction)**:
  - `SecretStore.swift`: `OPCSecretStatus` (platform-neutral codes mirroring
    OSStatus), `OPCSecretStoreProtocol`, `OPCAppPaths` (%APPDATA% on Windows,
    Application Support on Apple)
  - `OPCKeychainSecretStore` adapter bridges Keychain to the protocol;
    `Security` framework dependency is now confined to `KeychainStore.swift`
    (enforced by a new source-scan guard test)
  - 2 new invariant tests (578 total)

## [0.1.1] - 2026-09-06

### Fixed
- **Release publication**: the v0.1.0 release had been sitting in draft state
  since the history rewrite — `brew install` and every README download link
  returned 404. Published, and the Homebrew cask `sha256` re-synced to the
  current asset (it had drifted after repeated asset rebuilds)
- **Language switching (root cause, 4 structural bugs)**
  - Switch-time data refresh moved into `L10nEnvironment.didSet` — the previous
    view-level `.onChange` never fired because `.id(resolved)` rebuilt the view
    tree first (PR #3)
  - 40 `static let` localized constants converted to computed properties; they
    previously froze the language of their first access (PR #3)
  - 9 persisted-data matching collections (maintenance/delivery classification,
    CLI diagnostic prefixes, interaction-profile signal arrays) converted to
    bilingual unions, so data created in either language always matches (PR #3)
  - Builtin agent display names and job titles now follow the session language
    in both directions, including legacy debris forms such as
    `Chief 技术负责人` → `Chief CTO` (PR #2, PR #3)
  - Warmup terminal logs re-render symmetrically (zh ↔ en) regardless of the
    language they were generated in (PR #1)
  - System welcome notices in the chat bubble re-map to the current language (PR #1)
  - Window title, seat/people labels, and prefixed/interpolated `.L()` keys
    that could never hit the translation table
- **Privacy**
  - Product root paths are displayed tilde-abbreviated (`~/Library/...`) in the
    Command Center header — no usernames leak into screenshots
  - Demo capture script rewritten to window-only capture (never records the desktop)
- **Performance**
  - SpriteKit office scene is cached across SwiftUI body evaluations; it was
    previously rebuilt on every store mutation (visible stutter during terminal
    streaming)

### Added
- CI workflow (`.github/workflows/ci.yml`): build + full test suite on every
  push and pull request (PR #4)
- `scripts/verify-release.sh`: checks the release is published, the public
  asset URL downloads, and the Homebrew cask sha256 matches — run after every
  asset rebuild
- Language menu now shows what "Follow System / Auto" resolves to, and the
  currently effective language
- Test suite grown to 576 tests, including language-switch regression guards

## [0.1.0] - 2026-08-31

### Added
- Initial public release
- 2D pixel-art "company" visualization of AI coding agents (Claude Code, Codex,
  Gemini CLI, API models, local placeholders)
- Boss → CTO → employee task orchestration with approval gates and delivery
  acceptance
- Terminal Hall with per-employee persistent sessions and auto-interaction loops
- Full bilingual UI (Simplified Chinese / English) with in-app language switcher
- English translations of all core documentation
- Homebrew tap installation (`brew install --cask B1ueMu3ic4m/tap/opc-company`)
- 568 tests, MIT license, issue templates, contributing guide

[0.1.1]: https://github.com/B1ueMu3ic4m/OPCCompany/releases/tag/v0.1.0
[0.1.0]: https://github.com/B1ueMu3ic4m/OPCCompany/releases/tag/v0.1.0
