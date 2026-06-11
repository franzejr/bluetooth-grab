#!/usr/bin/env bash
#
# build-app.sh — package bluetooth-grab.sh into a double-clickable "Bluetooth Grab.app".
#
# Run this once (and again whenever you change bluetooth-grab.sh):
#     ./build-app.sh
# Then double-click "Bluetooth Grab.app" — or drag it to your Dock.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/Bluetooth Grab.app"
CONTENTS="$APP/Contents"

rm -rf "$APP" "$HERE/Magic Grab.app"   # drop the old name if it's lying around
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

# Bundle the script as a resource so the app is self-contained.
cp "$HERE/bluetooth-grab.sh" "$CONTENTS/Resources/bluetooth-grab.sh"
chmod +x "$CONTENTS/Resources/bluetooth-grab.sh"

# Bundle the Bluetooth icon if it's been generated (see make-icon.swift).
ICON_LINE=""
if [ -f "$HERE/AppIcon.icns" ]; then
  cp "$HERE/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
  ICON_LINE='  <key>CFBundleIconFile</key><string>AppIcon</string>'
fi

# The launcher the .app actually runs — it just calls the bundled script.
cat > "$CONTENTS/MacOS/BluetoothGrab" <<'LAUNCH'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")/../Resources" && pwd)"
exec "$DIR/bluetooth-grab.sh"
LAUNCH
chmod +x "$CONTENTS/MacOS/BluetoothGrab"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Bluetooth Grab</string>
  <key>CFBundleDisplayName</key><string>Bluetooth Grab</string>
  <key>CFBundleIdentifier</key><string>com.franzejr.bluetoothgrab</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleExecutable</key><string>BluetoothGrab</string>
  <key>CFBundlePackageType</key><string>APPL</string>
$ICON_LINE
</dict>
</plist>
PLIST

echo "Built: $APP"
echo "Double-click it, or run with --choose to re-pick devices:"
echo "  '$CONTENTS/Resources/bluetooth-grab.sh' --choose"
