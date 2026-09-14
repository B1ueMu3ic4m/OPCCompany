#!/usr/bin/env bash
# build-shell-macos.sh — package the Flutter shell as a standalone .app with
# the bridge dylib INSIDE the bundle (no DYLD env vars, no sibling .build
# assumption). Proof bar: the packaged app, launched with only its own
# bundle + an isolated support dir, must produce a shell-smoke ALL PASS.
#
#   bash scripts/build-shell-macos.sh            # build + bundle + prove
#   SKIP_PROVE=1 bash scripts/build-shell-macos.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_DIR="$ROOT/flutter_shell"
OUT="$ROOT/dist"
APP="$OUT/OPCCompanyShell.app"

echo "==> swift build (debug bridge)"
cd "$ROOT"
swift build --product OPCCompanyBridge
DYLIB="$(swift build --show-bin-path)/libOPCCompanyBridge.dylib"
[[ -f "$DYLIB" ]] || { echo "dylib not built"; exit 1; }

echo "==> flutter build macos (release)"
cd "$SHELL_DIR"
flutter build macos --release

echo "==> bundle the dylib into Contents/Frameworks (@rpath-resident)"
mkdir -p "$OUT"
APP_NAME="$(cat macos/Flutter/ephemeral/.app_filename 2>/dev/null || echo opc_flutter_shell.app)"
SRC_APP="build/macos/Build/Products/Release/$APP_NAME"
[[ -d "$SRC_APP" ]] || { echo "release app not found at $SRC_APP"; exit 1; }
rsync -a --delete "$SRC_APP/" "$APP/"
BIN="$APP/Contents/MacOS/${APP_NAME%.app}"
mkdir -p "$APP/Contents/Frameworks"
cp "$DYLIB" "$APP/Contents/Frameworks/libOPCCompanyBridge.dylib"
# The dylib must resolve from inside the bundle: Flutter's release binary
# ALREADY ships LC_RPATH @executable_path/../Frameworks (first real run of
# this script proved it — install_name_tool called "duplicate"), so we only
# verify presence, never mutate. (grep via variable, not a pipe: `set -o
# pipefail` turns `otool | grep -q` into a fake failure via SIGPIPE.)
RPATHS="$(otool -l "$BIN")"
if [[ "$RPATHS" != *"path @executable_path/../Frameworks"* ]]; then
    echo "unexpected: release binary lacks the Frameworks rpath"; exit 1
fi
codesign --force --deep --sign - "$APP" 2>/dev/null || true

if [[ "${SKIP_PROVE:-}" == "1" ]]; then
    echo "BUILT (prove skipped): $APP"; exit 0
fi

echo "==> prove: launch packaged app, isolated support dir"
PROVE_DIR="$(mktemp -d /tmp/opc-shell-prove.XXXX)"
# seed from the real snapshot so the UI has a company to mirror
REAL="$HOME/Library/Application Support/OPCCompany/company-state.json"
[[ -f "$REAL" ]] && cp "$REAL" "$PROVE_DIR/company-state.json"

RESULT="$PROVE_DIR/verdict.json"
OPC_SHELL_SMOKE=1 OPC_SHELL_SMOKE_OUT="$RESULT" \
    OPC_COMPANY_SUPPORT_DIR="$PROVE_DIR" \
    "$BIN" >/dev/null 2>&1 &
APP_PID=$!

for _ in $(seq 1 60); do
    sleep 1
    kill -0 "$APP_PID" 2>/dev/null || break
done
kill "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true

if [[ -f "$RESULT" ]] && grep -q '"ok":true' "$RESULT"; then
    echo "PROVED: packaged app self-check ALL PASS (dylib found inside bundle)"
    rm -rf "$PROVE_DIR"
    echo "OK: $APP"
else
    echo "FAIL: packaged app verdict missing or not ok — $RESULT left for debug"
    exit 1
fi
