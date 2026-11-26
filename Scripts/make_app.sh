#!/usr/bin/env bash
# Build the release binary and wrap it as a macOS .app bundle, so it gets a
# Dock entry and can be opened by name. Same shape as the sibling apps.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)

APP_NAME="Concierge"
DISPLAY_NAME="Concierge"
BUNDLE_ID="local.jeffdekerj.concierge"
APP_DIR="$ROOT/$APP_NAME.app"

# shellcheck source=Scripts/swift-build-flags.sh
source "$ROOT/Scripts/swift-build-flags.sh"

echo "Building release binary…"
swift build -c release "${SWIFT_BUILD_FLAGS[@]}"

echo "Assembling $APP_DIR …"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp ".build/release/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
# Resources/make_icon.py draws the icon; AppIcon.icns is committed so a build
# needs no Python.
cp "Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

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
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSRequiresAquaSystemAppearance</key><false/>
    <key>NSMicrophoneUsageDescription</key><string>Concierge listens when you talk to it, and for a few seconds after it says an alert.</string>
    <key>NSSpeechRecognitionUsageDescription</key><string>Concierge turns what you say into a question, on this Mac.</string>
</dict>
</plist>
PLIST

# Sign with the Mac's stable local identity when it exists, so the Full Disk
# Access grant (needed to read the WhatsApp database) survives rebuilds; else
# ad-hoc, which Gatekeeper accepts but macOS treats as a new app each time.
# Scripts/make_signing_cert.sh creates the identity once.
SIGN_ID="${CODESIGN_IDENTITY:-Finance Advisor Dev}"
SIGN_MODE="ad-hoc"
sign_bundle() {
    if codesign --force --deep --sign "$SIGN_ID" "$1" >/dev/null 2>&1; then
        SIGN_MODE="stable identity '$SIGN_ID'"
    else
        codesign --force --deep --sign - "$1" >/dev/null 2>&1 || echo "warning: codesign failed for $1"
    fi
}
sign_bundle "$APP_DIR"
touch "$APP_DIR"
if [ "$SIGN_MODE" = "ad-hoc" ]; then
    echo "Signed ad-hoc: run Scripts/make_signing_cert.sh once so Full Disk Access survives rebuilds."
else
    echo "Signed with $SIGN_MODE."
fi

# Keep an installed copy in ~/Applications in step, if there is one.
if [ -d "$HOME/Applications/$APP_NAME.app" ] || [ "${INSTALL:-}" = "1" ]; then
    INSTALLED="$HOME/Applications/$APP_NAME.app"
    rm -rf "$INSTALLED"
    cp -R "$APP_DIR" "$INSTALLED"
    sign_bundle "$INSTALLED"
    echo "Synced: $INSTALLED"
fi

echo
echo "Built: $APP_DIR"
echo "Run:   open '$APP_DIR'"
