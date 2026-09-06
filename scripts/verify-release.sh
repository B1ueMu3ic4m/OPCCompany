#!/bin/bash
# Verify the public release is actually installable:
#  1. the latest release is published (not draft) and tagged
#  2. the zip asset downloads from its PUBLIC URL (unauthenticated)
#  3. its sha256 matches what the Homebrew cask declares
# Run: bash scripts/verify-release.sh   (needs gh auth for the cask lookup;
# set GH_TOKEN or use `gh` — the asset download itself is public)
set -euo pipefail
REPO="B1ueMu3ic4m/OPCCompany"
TAP="B1ueMu3ic4m/homebrew-tap"

echo "[1/3] release state…"
TAG=$(gh api "repos/$REPO/releases/latest" --jq '.tag_name + " draft=" + (.draft|tostring)')
echo "  $TAG"
case "$TAG" in *"draft=true"*) echo "FAIL: latest release is a draft — brew/README downloads 404"; exit 1;; esac
VERSION=${TAG%% *}

echo "[2/3] public asset download…"
URL="https://github.com/$REPO/releases/download/$VERSION/OPCCompany-$VERSION.zip"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
HTTP=$(curl -sL -o "$TMP" -w '%{http_code}' "$URL")
if [ "$HTTP" != "200" ]; then echo "FAIL: $URL → HTTP $HTTP"; exit 1; fi
ACTUAL=$(shasum -a 256 "$TMP" | cut -d' ' -f1)
echo "  ok ($(wc -c < "$TMP" | tr -d ' ') bytes)"

echo "[3/3] cask sha256 match…"
DECLARED=$(gh api "repos/$TAP/contents/Casks/opc-company.rb" --jq '.content' | base64 -d | sed -n 's/.*sha256 "\(.*\)".*/\1/p')
if [ "$ACTUAL" = "$DECLARED" ]; then
  echo "  ok: $ACTUAL"
else
  echo "FAIL: asset sha $ACTUAL ≠ cask sha $DECLARED — update the cask"
  exit 1
fi
echo "release verification passed"
