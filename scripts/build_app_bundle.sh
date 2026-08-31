#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="OPCCompany"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BUILD_VERSION="${OPC_BUILD_VERSION:-$(date -u +%Y%m%d%H%M%S)}"
BUILT_AT_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cd "$ROOT_DIR"
swift "$ROOT_DIR/scripts/generate_app_icon.swift" "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/.build/release/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
cp "$ROOT_DIR/Assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>OPCCompany</string>
    <key>CFBundleIdentifier</key>
    <string>local.opc.company</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>OPC Company</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

{
    printf 'app: %s\n' "$APP_NAME"
    printf 'bundle_identifier: %s\n' "local.opc.company"
    printf 'build_version: %s\n' "$BUILD_VERSION"
    printf 'built_at_utc: %s\n' "$BUILT_AT_UTC"
    printf 'source_root: %s\n' "$ROOT_DIR"
} > "$RESOURCES_DIR/BuildInfo.txt"

if [[ "${OPC_SKIP_ADHOC_SIGN:-0}" != "1" ]]; then
    if command -v codesign >/dev/null 2>&1; then
        # Current bundle has no embedded helpers/frameworks; sign nested components explicitly if that changes.
        codesign --force --sign - "$APP_DIR"
    else
        echo "warning: codesign not found; bundle remains unsigned" >&2
    fi
fi

echo "$APP_DIR"
