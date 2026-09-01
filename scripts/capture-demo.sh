#!/bin/bash
# Capture demo screenshots for OPCCompany README — WINDOW-ONLY capture (privacy-safe).
# PREREQUISITE: grant Screen Recording permission to your terminal app
# (System Settings → Privacy & Security → Screen & System Audio Recording).
# Usage: bash scripts/capture-demo.sh   (outputs to docs/assets/)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=docs/assets
mkdir -p "$OUT"

# Resolve the OPC Company window id (window-only capture; never full screen)
WID=$(/usr/bin/swift - <<'SWIFT'
import CoreGraphics
import Foundation
let opts = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
if let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] {
    for w in list {
        let owner = w["kCGWindowOwnerName"] as? String ?? ""
        if owner.contains("OPC"), let num = w["kCGWindowNumber"] as? Int {
            print(num); exit(0)
        }
    }
}
print("NONE")
SWIFT
)
if [ "$WID" = "NONE" ]; then echo "OPC Company window not found — launch the app first"; exit 1; fi
echo "Capturing OPC Company window #$WID (window-only)"

shot() { screencapture -x -o -l "$WID" "$1"; echo "saved $1"; }

echo "[1/4] Command Center / Company Floor"
shot "$OUT/shot-command-center.png"
echo "[2/4] Open the Add Employee sheet (⌘⇧N), then press Enter…"
read -r
shot "$OUT/shot-add-employee.png"
echo "[3/4] Go to Terminal Hall, run one employee, then press Enter…"
read -r
shot "$OUT/shot-terminal-hall.png"
echo "[4/4] Product Detail (optional, press Enter to capture)…"
read -r
shot "$OUT/shot-product-detail.png"

echo "Done. Files in docs/assets/ (window-only, no desktop content)."
