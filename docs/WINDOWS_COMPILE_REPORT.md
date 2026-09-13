# Windows Compile Report (M1 results)

Date: 2026-09-08 · Spike run: [34181655228](https://github.com/B1ueMu3ic4m/OPCCompany/actions/runs/34181655228) (all steps green) · Artifacts: `windows-spike-logs`

## How to reproduce

Trigger **"Windows Port Spike (M1)"** via `workflow_dispatch` — the workflow
installs Swift 6.3.3 on a `windows-2022` runner (Burn `/quiet` + `SDKROOT`,
per scoop's recipe) and runs `scripts/windows-spike.ps1`.

## Environment findings (what it took to get a working compiler)

| Problem | Solution |
|---|---|
| Swift installer is a WiX **Burn** bundle (not Inno) | run it with `/quiet /norestart` — never `/VERYSILENT` |
| `unable to load standard library` | set `SDKROOT=<platform>\Developer\SDKs\Windows.sdk` (scoop's mechanism; registry keys are NOT how swift-driver finds the stdlib) |
| `swift.exe` silent crash 0xC0000135 | toolchain DLL dirs must be on PATH (`Runtimes\usr\bin`, `Toolchains\usr\bin`) |
| VS 2026 image breaks SDK detection | pin `windows-2022` (VS 17 toolset, officially supported) |

## Compile census (the actual data)

Logic-only package (29 non-UI core files) → **138 error lines, from exactly
two Apple-only modules**:

| Module | Errors | Files that import it | Cross-platform replacement |
|---|---|---|---|
| `CryptoKit` | 60 | `CommunicationInboundVerifier.swift` | [swift-crypto](https://github.com/apple/swift-crypto) (`import Crypto`) — official, same API |
| `SwiftUI` | 76 | `CompanyStore.swift`, `+Agents`, `+Persistence`, `+Workspace`, `L10nEnvironment.swift` (only for `ObservableObject`/`@Published`) | [OpenCombine](https://github.com/OpenCombine/OpenCombine) provides both on Windows |

Zero errors from: `Security`*, `SQLite3`, `Foundation`, `Dispatch`, linking.
(*build aborted early; `Security` is already confined to `KeychainStore.swift`
by M0, with the Windows DPAPI store planned in issue #11.)

Full-package build additionally fails only in the 12k-line SwiftUI/SpriteKit
UI layer — expected, that's the layer a Windows frontend replaces.

## Spike #2 re-run (2026-09-08, run 34184777279) — shims verified

After PR #41 (CryptoKit→swift-crypto, SwiftUI observation→ObservationCompat):

| Module | M1 census | Spike #2 |
|---|---|---|
| CryptoKit | 60 errors | **0** — swift-crypto compiled 461/461 files on MSVC |
| SwiftUI (observation) | 76 errors | **0** in the logic package — compat layer verified |
| SQLite3 | 0 (not reached) | **62 errors, 6 files** — next real blocker |
| Security | 0 (not reached) | queued behind SQLite3 (issue #11) |

The logic build now executes 484 compile jobs (vs aborting at manifest stage in
M1) — both shims work on real Windows, not just on paper. Remaining core-layer
work: a SQLite3 strategy (issue #42) + the DPAPI/file secret store (issue #11).
UI-layer SwiftUI/SpriteKit errors (full-package build) are expected — that is
the layer the Flutter frontend replaces.

## Spike #3 (2026-09-08, run 34188210218) — SQLite verified, Security last

After PR #44 (vendored `CSQLite`, per-file import switch):

| Module | Spike #2 | Spike #3 |
|---|---|---|
| SQLite3 | 62 errors | **0** — vendored amalgamation compiles under MSVC |
| Security | not reached | **62 — ALL from `KeychainStore.swift`**, exactly as the static audit predicted |
| SwiftUI (logic pkg) | 0 | 0 |

The census's 78 SwiftUI errors are all in **UI-layer files** (AddEmployeeSheet
×40, TerminalHallView, …) — out of scope for the logic package; the Flutter UI
(M3) replaces them wholesale.

PR #45 (merged after this run started) gates `KeychainStore.swift` behind
`#if canImport(Security)` with a **fail-closed** Windows placeholder (refuses
saves → boss-visible risk event; no plaintext interim). Spike #4
(run 34190104162) is the expected **zero-blocker** confirmation for the logic
package.

## Spike #4 (2026-09-08, run 34190104162) — Security verified, ObjC last

| Module | Spike #3 | Spike #4 |
|---|---|---|
| Security | 62 errors | **0** — PR #45 verified on real Windows |
| SQLite3 / CryptoKit / SwiftUI (logic) | 0 | 0 |
| ObjectiveC | not reached | **62 — ALL from `L10nBundleOverride.swift`** (the Bundle.main swizzle, issue #10's mechanism) |

The census peeled exactly one layer per round, each fix verified by the next
run. PR #47 gates the swizzle behind `#if canImport(ObjectiveC)` with a
same-API no-op recorder on Windows (the swizzle only serves SwiftUI
`Text("literal")` lookups, which don't exist there; dynamic strings keep
working via the neutral `.L()` path). Spike #5 = expected zero-blocker
confirmation for the logic package.

## Spike #6 (2026-09-08, run 34215450265) — M0 CLOSED: zero errors on Windows

After PR #49 (five cross-layer fixes), the **logic package builds on real
Windows with zero errors**: 496/496 compile jobs, `Build complete! (334.09s)`.
The census's remaining 83 errors all belong to the *full*-package UI files
(AddEmployeeSheet etc.) — M3 Flutter scope, not the portable core.

| Round | Blockers peeled (all verified by the next run) |
|---|---|
| #1 (M1) | CryptoKit 60, SwiftUI-observation 76 |
| #2 | SQLite3 62 |
| #3 | Security 62 (predicted by static audit first) |
| #4 | ObjectiveC 62 |
| #5 | cross-layer 420 (FoundationNetworking ×50, missing-Foundation ×42, POSIX kill ×32, logic-in-UI ×84) |
| **#6** | **0 — M0 portability milestone achieved** |

First Windows-path artifact: the `opc` headless CLI (v0.2.0) links only this
verified core.

## Spike #7–#8 (2026-09-12, runs 34684564763 → 34687031765) — DPAPI on real Windows

Spike #7 (run 34684564763) exposed that DPAPISecretStore (PR #53) never
compiled on Windows — `LPCWSTR` description param, a `Self.`-less static
call, and (by review) dangling `&localVar` pointers across statements.
Fixed in PR #54; the same run also exposed a false-POSITIVE milestone gate
(full-package UI noise satisfying `Build complete`).

Spike #8 (run 34687031765, PR #54's gate + fixed store):

| Signal | Value (from artifact, not gate) |
|---|---|
| core-error-lines | **0** |
| probe-save | **true** |
| probe-load-match | **true** |
| probe-ciphertext-on-disk | **true** — API keys at rest are DPAPI ciphertext |
| probe-delete | **true** |

The gate still said False — its matcher expected `:True` while Swift prints
lowercase `true` (false-NEGATIVE; fixed in PR #55 with `(?i)` + regex-escaped
concatenation and per-line green reporting). Spike #9 confirms the full
honest chain: clean compile + live probe + truthful verdict.

## Spike #9 (2026-09-13, run 34734919125) — MILESTONE, gate-verified ✅

First run where every layer of the story agrees, with the per-signal gate
from #55:

```
probe probe-save: green=True
probe probe-load-match: green=True
probe probe-ciphertext-on-disk: green=True
probe probe-delete: green=True
DPAPI probe all-green: True (core errors: 0)
SPIKE MILESTONE: logic package builds CLEAN on Windows + DPAPI runtime verified
```

**M0 is closed with runtime evidence, not just compile evidence**: the full
business-logic layer compiles with zero errors on Windows AND the DPAPI
secret store was exercised live (encrypt → persist ciphertext → decrypt →
delete). Issue #11 closed. Remaining census errors are UI-layer only
(M3 Flutter scope).

## Spike #10 (windows.yml production CI, 2026-09-13) — experiment-vs-product drift caught

The new continuous Windows build (PR #57) failed on its FIRST run with
`no such module 'SwiftUI'` on `AddEmployeeSheet.swift` — inside the MAIN
OPCCompanyCore target. Nine green spikes never saw this because the spike
package compiles a curated 33-file manifest that excludes all pure-view
files, while the real target includes everything in the directory.

This was the last architectural gap M0 claimed to close: "the logic package
builds clean on Windows" was true OF THE SPIKE MANIFEST, not of the shipping
product. Fixed the same day: all 8 pure-view files (AddEmployeeSheet,
CommandCenterView, CompanyScene, ContentView, InspectorPanel,
OperationsSuiteView, SelectionWorkspaceView, TerminalHallView) got whole-file
`#if canImport(SwiftUI)` gates — empty units on Windows until M3's Flutter
shell replaces them.

Honest tally of what each layer proves:
| layer | proof |
|---|---|
| spike manifest (33 logic files) | ✅ compiles + DPAPI runtime probe green |
| **main product target (all 41 files)** | ⏳ pending PR #57 re-run |
| opc.exe from the main package, launched in CI | ⏳ same run |

Lesson (the same class as gate false-positives): **a hand-curated
build list is not the product**. Continuous CI against the real package is
what turns "ported" from a spike claim into a standing guarantee.

## Verdict (per the RFC decision tree)

Route A gate was "core compiles with < ~20 blocking errors". Actual across
three spikes: **3 blocking modules total (CryptoKit, SwiftUI-observation,
SQLite3) + Security confinement — every one now shimmed and individually
verified on real Windows** (60→0, 76→0, 62→0, 62→fix merged). →

**Route A is GO**: keep the Swift core (with `#if canImport` shims), expose it
to a Flutter desktop UI via FFI. Remaining tracked work: #9 (ProcessRunner),
#10 (i18n swizzle), #11 (real DPAPI store replacing the fail-closed stub).
Route C (community port) stays open in parallel.

## Next steps

1. ~~M0 shims~~ ✅ done & spike-verified: CryptoKit (#41), SwiftUI observation
   (#41), SQLite3 (#44), Security confinement (#45)
2. Spike #4 (running): expected 0 blocking modules in the logic package —
   the proof that the core is fully portable
3. Then: FFI surface design + Flutter UI skeleton (M3); issue #11 (DPAPI)
   can proceed in parallel as community work
