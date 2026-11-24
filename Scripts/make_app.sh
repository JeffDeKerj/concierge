#!/usr/bin/env bash
# Build the release binary and wrap it as a macOS .app bundle, so it gets a
# Dock entry and can be opened by name. Same shape as the sibling apps.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)

APP_NAME="ClaudeAssistant"
DISPLAY_NAME="Briefing"
BUNDLE_ID="local.jeffdekerj.claude-assistant"
APP_DIR="$ROOT/$APP_NAME.app"

# shellcheck source=Scripts/swift-build-flags.sh
source "$ROOT/Scripts/swift-build-flags.sh"

echo "Building release binary…"
swift build -c release "${SWIFT_BUILD_FLAGS[@]}"

echo "Assembling $APP_DIR …"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp ".build/release/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$DISPLAY_NAME</string>
    <key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSRequiresAquaSystemAppearance</key><false/>
</dict>
</plist>
PLIST

# Ad-hoc sign so Gatekeeper does not refuse the bundle outright.
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
touch "$APP_DIR"

# Keep an installed copy in ~/Applications in step, if there is one.
if [ -d "$HOME/Applications/$APP_NAME.app" ] || [ "${INSTALL:-}" = "1" ]; then
    INSTALLED="$HOME/Applications/$APP_NAME.app"
    rm -rf "$INSTALLED"
    cp -R "$APP_DIR" "$INSTALLED"
    codesign --force --deep --sign - "$INSTALLED" >/dev/null 2>&1 || true
    echo "Synced: $INSTALLED"
fi

echo
echo "Built: $APP_DIR"
echo "Run:   open '$APP_DIR'"
