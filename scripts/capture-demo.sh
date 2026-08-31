#!/bin/bash
# Capture demo screenshots & GIF source for OPCCompany README.
# PREREQUISITE: grant Screen Recording permission to your terminal app
# (System Settings → Privacy & Security → Screen & System Audio Recording).
# Usage: bash scripts/capture-demo.sh   (outputs to docs/assets/)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=docs/assets
mkdir -p "$OUT"

shot() { screencapture -x "$1"; echo "saved $1"; }

echo "[1/4] Launch app (English mode)…"
OPC_FORCE_LANGUAGE=en dist/OPCCompany.app/Contents/MacOS/OPCCompany &
APP=$!
sleep 6

echo "[2/4] Screenshots"
shot "$OUT/shot-command-center.png"    # Command Center + company floor
echo "   → open the Add Employee sheet (⌘⇧N), press Enter to continue…"
read -r
shot "$OUT/shot-add-employee.png"
echo "   → go to Terminal Hall, run one employee, press Enter…"
read -r
shot "$OUT/shot-terminal-hall.png"

echo "[3/4] GIF: company floor (8s)"
ffmpeg -y -f avfoundation -framerate 30 -capture_cursor 1 -i "1:0" -t 8 \
  -vf "fps=15,scale=1024:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" \
  "$OUT/demo-floor.gif" || echo "ffmpeg avfoundation failed — record with QuickTime and convert manually"

echo "[4/4] Done. Review files, then delete placeholders:"
ls -la "$OUT"
kill $APP 2>/dev/null || true
