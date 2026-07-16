#!/usr/bin/env bash
#
# build-app.sh — compile the SwiftUI app and package it into "Bluetooth Grab.app".
#
# Run this once (and again whenever you change the sources):
#     ./build-app.sh
# Then double-click "Bluetooth Grab.app" — or drag it to your Dock.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/Bluetooth Grab.app"
CONTENTS="$APP/Contents"
BINARY_NAME="BluetoothGrab"

echo "Compiling (release)…"
swift build -c release --package-path "$HERE"
BUILT_BINARY="$(swift build -c release --package-path "$HERE" --show-bin-path)/$BINARY_NAME"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

# Drop the compiled binary in as the app's executable.
cp "$BUILT_BINARY" "$CONTENTS/MacOS/$BINARY_NAME"
chmod +x "$CONTENTS/MacOS/$BINARY_NAME"

# Bundle the app icon if it's been generated (see make-icon.swift).
ICON_LINE=""
if [ -f "$HERE/AppIcon.icns" ]; then
  cp "$HERE/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
  ICON_LINE='  <key>CFBundleIconFile</key><string>AppIcon</string>'
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Bluetooth Grab</string>
  <key>CFBundleDisplayName</key><string>Bluetooth Grab</string>
  <key>CFBundleIdentifier</key><string>com.franzejr.bluetoothgrab</string>
  <key>CFBundleVersion</key><string>2.0</string>
  <key>CFBundleShortVersionString</key><string>2.0</string>
  <key>CFBundleExecutable</key><string>$BINARY_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSBluetoothAlwaysUsageDescription</key><string>Bluetooth Grab needs Bluetooth access to move your paired devices onto this Mac.</string>
$ICON_LINE
</dict>
</plist>
PLIST

# Sign the bundle (ad-hoc) AFTER writing Info.plist. Without a signature that
# seals the NSBluetoothAlwaysUsageDescription string, macOS aborts blueutil with
# SIGABRT the moment it touches Bluetooth (instead of prompting for permission).
codesign --force --sign - --identifier com.franzejr.bluetoothgrab "$APP"

echo "Built: $APP"
echo "Open it with:  open '$APP'"
echo "On first launch, allow the Bluetooth permission prompt so blueutil can run."
