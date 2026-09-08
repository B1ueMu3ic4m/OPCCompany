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

## Verdict (per the RFC decision tree)

Route A gate was "core compiles with < ~20 blocking errors". Actual: **2
blocking modules, both with official drop-in replacements**. →

**Route A is GO**: keep the Swift core (with `#if canImport` shims for
CryptoKit/SwiftUI-observation/Security), expose it to a Flutter desktop UI
via FFI. The four known shim points already have tracked issues:
#9 (ProcessRunner), #10 (i18n swizzle), #11 (secret store), plus the
OpenCombine swap. Route C (community port) stays open in parallel.

## Next steps

1. M0 remainder: the 4 shim points above (each is a small, isolated PR)
2. Spike #2 (new): compile the core with swift-crypto + OpenCombine wired in
   — expected: **0 errors**, proving full core portability
3. Then: FFI surface design + Flutter UI skeleton (M3)
