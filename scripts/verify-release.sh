#!/bin/bash
# Verify the public release is actually installable:
#  1. the latest release is published (not draft) and tagged
#  2. the zip asset downloads from its PUBLIC URL (unauthenticated)
#  3. its sha256 matches what the Homebrew cask declares
#  4. the Windows shell preview package (when published) carries a bridge
#     DLL whose six ABI symbols are real PE exports — structural check via
#     scripts/pe_check.py, replacing byte-string grepping. Import table is
#     printed for honesty (runtime-bundling status), not gated: v0.3.1's
#     README openly states the Swift runtime must be installed separately.
# Run: bash scripts/verify-release.sh   (needs gh auth for the cask lookup;
# set GH_TOKEN or use `gh` — the asset download itself is public)
set -euo pipefail
REPO="B1ueMu3ic4m/OPCCompany"
TAP="B1ueMu3ic4m/homebrew-tap"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

echo "[1/4] release state…"
TAG=$(gh api "repos/$REPO/releases/latest" --jq '.tag_name + " draft=" + (.draft|tostring)')
echo "  $TAG"
case "$TAG" in *"draft=true"*) echo "FAIL: latest release is a draft — brew/README downloads 404"; exit 1;; esac
VERSION=${TAG%% *}

echo "[2/4] public asset download…"
URL="https://github.com/$REPO/releases/download/$VERSION/OPCCompany-$VERSION.zip"
TMP=$(mktemp)
SHELL_TMP=$(mktemp)
SHELL_DIR=""
trap 'rm -f "$TMP" "$SHELL_TMP"; [ -n "$SHELL_DIR" ] && rm -rf "$SHELL_DIR"' EXIT
HTTP=$(curl -sL -o "$TMP" -w '%{http_code}' "$URL")
if [ "$HTTP" != "200" ]; then echo "FAIL: $URL → HTTP $HTTP"; exit 1; fi
ACTUAL=$(shasum -a 256 "$TMP" | cut -d' ' -f1)
echo "  ok ($(wc -c < "$TMP" | tr -d ' ') bytes)"

echo "[3/4] cask sha256 match…"
DECLARED=$(gh api "repos/$TAP/contents/Casks/opc-company.rb" --jq '.content' | base64 -d | sed -n 's/.*sha256 "\(.*\)".*/\1/p')
if [ "$ACTUAL" = "$DECLARED" ]; then
  echo "  ok: $ACTUAL"
else
  echo "FAIL: asset sha $ACTUAL ≠ cask sha $DECLARED — update the cask"
  exit 1
fi

echo "[4/4] Windows shell preview package exports…"
# The shell package is versioned but not covered by the cask; find it by
# listing the release's assets. A release without one (macOS-only tags)
# passes vacuously but says so explicitly.
SHELL_ASSET=$(gh api "repos/$REPO/releases/latest" --jq '.assets[].name' \
  | grep '^OPCCompanyShell-windows-x64-.*\.zip$' | head -1 || true)
if [ -z "$SHELL_ASSET" ]; then
  echo "  skip: no Windows shell asset on this release"
else
  SHELL_URL="https://github.com/$REPO/releases/download/$VERSION/$SHELL_ASSET"
  HTTP=$(curl -sL -o "$SHELL_TMP" -w '%{http_code}' "$SHELL_URL")
  if [ "$HTTP" != "200" ]; then echo "FAIL: $SHELL_URL → HTTP $HTTP"; exit 1; fi
  SHELL_DIR=$(mktemp -d)
  unzip -q -o "$SHELL_TMP" -d "$SHELL_DIR"
  DLL=$(find "$SHELL_DIR" -name OPCCompanyBridge.dll | head -1)
  if [ -z "$DLL" ]; then echo "FAIL: shell zip has no OPCCompanyBridge.dll"; exit 1; fi
  python3 "$SCRIPT_DIR/pe_check.py" exports "$DLL" \
    opc_bridge_create opc_bridge_destroy opc_bridge_command \
    opc_bridge_snapshot_json opc_bridge_last_error opc_bridge_free
  echo "  imports (informational — runtime bundling NOT gated):"
  python3 "$SCRIPT_DIR/pe_check.py" imports "$DLL" | sed 's/^/    /'
  echo "  ok: $SHELL_ASSET bridge exports structurally verified"
fi
echo "release verification passed"
