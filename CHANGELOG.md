# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Shell boss loop (M3)**: goal input bar + approvals queue with
  approve/reject (`decide`) in the Flutter shell — filing goals and
  resolving decisions now works headless of the SwiftUI app; snapshot
  selectors are junk-payload defensive (2 more unit tests, 5 total)
- **Audit-round hardening (2026-09-14)**:
  - Bridge stress suite (`OPCBridgeStressTests`, +6 tests → 593): NULL/
    malformed/1MB payloads through the real @_cdecl entries (refuse-clean,
    never trap), 25 create/destroy churn cycles, 250 returned-buffer frees
    (allocator-contract soak), 1000-call guard-latency budget, parameterized
    env matrix proving only exact "1" disables detection ("0"/""/yes must
    not — a semantic security hole), and 200-goal core scaling (≥800 tasks,
    snapshot-encode + save time-boxes). User live snapshot verified
    byte-identical across the whole run (isolation, not promises).
  - `.gitleaks.toml`: documented allowlist for the two accepted non-secret
    classes (SHA256-pinned vendored SQLite corpora + the DPAPI probe
    sentinel, incl. its earlier git-history name) — scan exits 0.
  - `scripts/scan-secrets.sh`: runs the policy locally by design — wiring
    gitleaks into CI would pull a third-party container image, widening the
    supply chain this same audit just hardened.
- **M3 first slice — the C-ABI bridge (`OPCBridge`)**: the portable core is
  now callable from non-Swift hosts. New dynamic-library product
  `OPCCompanyBridge` exports 6 C symbols (`opc_bridge_create/destroy/
  last_error/snapshot_json/command/free`, verified with `nm` on the built
  dylib); company state crosses as versioned JSON so the C header stays
  frozen while the schema evolves. Write verbs honor the same
  cross-process guard the CLI uses — extracted to core (`OPCWriteGuard`)
  so rule drift between entry points is structurally impossible.
  Host contract: `malloc`-allocated returns (Dart `malloc.free` /
  C `free()` compatible); callable from any host thread — the bridge hops
  onto the main queue internally (the first real host, a bare `dart run`
  FFI, disproved the original main-thread-trap design on smoke run #1).
  `include/opc_bridge.h` documents the ABI; a source-gate test keeps
  header ↔ exports in sync.
- 3 M3 guard tests (guard single-implementation, live bridge round-trip
  incl. double-create refusal + unknown-verb refusal, header/symbol sync)

## [0.2.1] - 2026-09-13

### Added
- **Continuous Windows CI (`windows.yml`)**: every push to main and every PR
  touching the portable core builds `opc.exe` with the EXACT toolchain
  sequence validated across spikes #5–#9 (Burn /quiet + machine-scope +
  DLL PATH + SDKROOT) and uploads it as an artifact. CI runs the binary
  (`opc.exe version` + `help`) — "compiles" can't regress to "links but
  won't launch".
- **Windows DPAPI secret store (closes #11)**: `OPCDPAPISecretStore` —
  per-user `CryptProtectData` via a header-only `CWinDPAPI` shim (same
  pattern as CSQLite; crypt32 linked Windows-only). API keys move from the
  fail-closed placeholder to real at-rest protection: ciphertext blobs under
  `secrets/<uuid>.blob`, app-domain entropy for channel binding,
  `CRYPTPROTECT_UI_FORBIDDEN`, UUID-whitelisted paths.
  `OPCKeychainSecretStore` routes there via typealias — zero call-site
  changes; fail-closed remains only where no DPAPI exists (Linux dev).
- **DPAPI runtime probe in the spike**: `spikeprobe` executes
  save→load-match→ciphertext-on-disk→delete on the real runner; the
  milestone gate requires all four lines + zero core errors. Spike #9
  printed the first honest **SPIKE MILESTONE** line.
- `VERSION` file = single source of truth for the app version, consumed by
  the bundle script, asserted against the CLI by a new consistency test
  (version literals previously lived in three places)
- 4 audit regression tests (CLI guard invariants, DPAPI wiring/path safety,
  version consistency, persistence anti-resurrection)

### Fixed
- **Bridge least privilege**: `opc_bridge_create` now pins
  `liveChatEnabled: false` — the bridge's verbs never send employee chats,
  so a shell must not inherit the GUI's default-on live-backend behavior
  through bootstrap's `liveChatEnabled ?? loadPersisted` default.
- CI least privilege: `permissions: contents: read` on all three workflows
  (was: repo-default, i.e. unbounded); flutter_shell ABI smoke dead map
  (`lookups`) removed.
- **CLI data-loss guard**: `opc goal`/`opc advance` refuse to run while
  OPCCompany.app is alive (pgrep, exact comm name — the CLI never
  self-matches, sequential CLI scripting stays safe). Previously a CLI save
  from stale-read state could silently rewind GUI changes.
  Override: `OPC_ALLOW_CONCURRENT_WRITE=1`
- **Whole-file SwiftUI gating for the 8 pure-view files** (windows.yml first
  run caught it): the main `OPCCompanyCore` target still compiled
  AddEmployeeSheet/CommandCenterView/CompanyScene/ContentView/InspectorPanel/
  OperationsSuiteView/SelectionWorkspaceView/TerminalHallView unconditionally
  → `no such module 'SwiftUI'` on Windows. The spike package (its own 33-file
  manifest) never included them, so nine green spikes masked this. Each is now
  `#if canImport(SwiftUI)` around the whole file — an empty unit on Windows
  until M3 replaces them with the Flutter shell.
- `sqlite3` was force-linked on all platforms: the Windows main-package
  build would request a non-existent `sqlite3.lib` (the spike package's
  separate manifest masked it; only the new continuous CI caught this).
  Now `.when(platforms:)`-gated — Apple links the OS copy, Windows uses the
  vendored CSQLite objects.
- DPAPI store fixed for real Windows (spike #7): `LPCWSTR` description
  param, `Self.`-qualified static call, and pointer-lifetime UB
  (`withUnsafeMutableBufferPointer` around the Crypt* calls)
- Windows/Linux `OPCObservationBus`: token-addressable listeners with
  `removeListener` (the append-only list would leak every future FFI
  client)
- Milestone-gate honesty (spikes #7→#8 lessons): core errors counted from
  the logic build only; probe matcher made case-insensitive against Swift's
  lowercase `true`; per-line green reporting

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
