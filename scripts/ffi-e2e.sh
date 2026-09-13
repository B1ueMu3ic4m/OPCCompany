#!/usr/bin/env bash
# ffi-e2e.sh — the shell's two-layer smoke, safe for local + CI:
#   layer 1 (ABI): pure `dart run` — dylib loads, 6 symbols resolve,
#                  malloc/free contract holds (bin/smoke.dart)
#   layer 2 (behavioral): the real Flutter macOS shell, headless env-gated
#                  (OPC_SHELL_SMOKE=1) — full create/snapshot/goal/advance/
#                  save/durability cycle on a runloop-pumping host
# Both run against an ISOLATED copy of the live snapshot (OPC_COMPANY_
# SUPPORT_DIR — HOME redirects do NOT move app-support on macOS).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DYLIB="$ROOT/.build/debug/libOPCCompanyBridge.dylib"
if [[ ! -f "$DYLIB" ]]; then
    echo "== building bridge dylib (debug)…"
    (cd "$ROOT" && swift build)
fi

WORK="$(mktemp -d /tmp/opc-ffi-e2e.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

LIVE="$HOME/Library/Application Support/OPCCompany/company-state.json"
[[ -f "$LIVE" ]] && cp "$LIVE" "$WORK/company-state.json"

cd "$ROOT/flutter_shell"
[[ -d .dart_tool ]] || flutter pub get >/dev/null

echo "== layer 1: pure-Dart ABI smoke"
OPC_BRIDGE_DYLIB="$DYLIB" dart run bin/smoke.dart

echo "== layer 2: Flutter shell behavioral smoke (macOS, headless env gate)"
# The shell resolves the bare soname — point dyld at the SwiftPM build dir.
export DYLD_LIBRARY_PATH="$ROOT/.build/debug:${DYLD_LIBRARY_PATH:-}"
export OPC_BRIDGE_DYLIB="$DYLIB"
export OPC_COMPANY_SUPPORT_DIR="$WORK"
export OPC_SHELL_SMOKE=1
export OPC_SHELL_SMOKE_OUT="$WORK/result.json"

flutter build macos --debug >/dev/null
APP="$ROOT/flutter_shell/build/macos/Build/Products/Debug/opc_flutter_shell.app"
"$APP/Contents/MacOS/opc_flutter_shell" >/tmp/opc-shell-smoke.log 2>&1 &
SHELL_PID=$!

# The app self-exits via exit() in finishShellSmoke; give it a hard ceiling.
for i in $(seq 1 60); do
    if ! kill -0 "$SHELL_PID" 2>/dev/null; then break; fi
    sleep 2
done
if kill -0 "$SHELL_PID" 2>/dev/null; then
    kill "$SHELL_PID" 2>/dev/null || true
    echo "SHELL SMOKE TIMEOUT"; cat /tmp/opc-shell-smoke.log; exit 1
fi

if [[ -f "$WORK/result.json" ]]; then
    cat "$WORK/result.json"
    grep -q '"ok":true' "$WORK/result.json" && echo "== E2E ALL GREEN" || { echo "== SHELL SMOKE FAILURES"; exit 1; }
else
    echo "no result.json — shell log tail:"; tail -20 /tmp/opc-shell-smoke.log; exit 1
fi
