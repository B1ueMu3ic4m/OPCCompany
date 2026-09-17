# OPC Flutter Shell (M3, in progress)

The cross-platform desktop shell for OPC Company. It is a **thin mirror**:
zero business logic lives here — the entire company runs in the portable
Swift core, reached over the C-ABI bridge (`../include/opc_bridge.h`,
implemented by `Sources/OPCCompanyCore/OPCBridge.swift`).

## Layout
```
lib/opc_bridge_bindings.dart   dart:ffi bindings (the six C symbols) — pure Dart, no Flutter dep
lib/shell_smoke.dart           headless behavioral smoke, enabled by OPC_SHELL_SMOKE=1
lib/main.dart                  Flutter skeleton: snapshot dashboard + Refresh/Advance
bin/smoke.dart                 pure-Dart ABI smoke (dylib loads, symbols resolve, malloc/free contract)
test/shell_smoke_test.dart     unit tests for the shell's data layer
```

## Running the smokes (what CI will do)
```bash
# from the repo root — builds the dylib if needed, runs BOTH layers against
# an ISOLATED copy of your snapshot:
scripts/ffi-e2e.sh
```
Layer 1 (ABI): `OPC_BRIDGE_DYLIB=…/libOPCCompanyBridge.dylib dart run bin/smoke.dart`
Layer 2 (behavior): the built shell app with `OPC_SHELL_SMOKE=1` writes a
machine-readable verdict and exits 0/1.

## Honest host contract (learned the hard way, smoke #1–#3)
The bridge hops its @MainActor store work onto the **process main queue**.
That is why the behavioral smoke runs inside the Flutter app (its platform
thread pumps the queue) and NOT under bare `dart run` (nothing pumps →
blocked-by-design). `bin/smoke.dart` deliberately covers only what any host
can prove: dlopen, symbol resolution, and the malloc/free allocator contract.

## Status
- [x] dart:ffi bindings + ABI smoke green (11/11 on macOS dylib)
- [x] behavioral cycle green (10/10: create/snapshot/goal→+4 chain/advance/save/refusals/durability)
- [x] snapshot dashboard skeleton
- [x] goal text field + approvals list UI (decide wired)
- [x] **transcript panel** — tap an employee chip to watch their terminal
      below the board; `terminal_digest`/`terminal_tail` query verbs feed it
      event-driven (digest-diff cursor, growth-window fetch, shrink reset)
- [x] **product switcher + dark identity** — AppBar menu switches workspaces
      via the bridge's `product_select` verb (unknown ids refused with a
      reason, never a silent no-op); shell now wears the macOS app's slate
      + gold palette
- [x] **standalone macOS .app** — `scripts/build-shell-macos.sh` bundles the bridge dylib into Frameworks and PROVES it: the packaged release app self-checks ALL PASS with no env tricks (`dist/OPCCompanyShell.app`)
- [x] **Windows package assembled + run in CI** — `windows-shell.yml`: bridge DLL (release) + `flutter build windows --release` (official pinned SDK) + DLL beside the exe + the assembled `opc_flutter_shell.exe` LAUNCHED against a fresh support dir → `verdict.json "ok":true` (10/10, same cycle as macOS). Artifact `opc-shell-windows-x86_64` is the user-runnable package.
- [ ] code signing + notarization / MSIX installers (release polish, not gating)
