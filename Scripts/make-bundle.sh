#!/usr/bin/env bash
# Mac-side packaging: build + assemble NeverSleep.app + icns from art/.
# Run on a Mac with Swift (any Xcode-less setup works since everything is SPM):
#   swift build -c release && ./Scripts/make-bundle.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/.build/release"
APP="$ROOT/build/NeverSleep.app"

echo "==> building"
(cd "$ROOT" && swift build -c release)

echo "==> assembling .app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/NeverSleep" "$APP/Contents/MacOS/NeverSleep"
cp "$BUILD/neversleepctl" "$APP/Contents/MacOS/neversleepctl" || true

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>NeverSleep</string>
  <key>CFBundleIdentifier</key><string>app.legba.neversleep</string>
  <key>CFBundleVersion</key><string>0.3.0</string>
  <key>CFBundleShortVersionString</key><string>0.3.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>NeverSleep</string>
  <key>CFBundleIconFile</key><string>NeverSleep</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
</dict></plist>
PLIST

echo "==> icon (rasterize art/neversleep-app-icon.svg -> icns)"
bash "$ROOT/Scripts/make-iconset.sh" "$APP/Contents/Resources/NeverSleep.icns"

echo "==> menubar state icons (art/menubar-z-{active,inactive}.svg -> vector PDFs)"
# Both must exist for the filled-vs-outline status swap (NoSleep parity #3); die if missing.
for state in active inactive; do
  rsvg-convert -f pdf -o "$APP/Contents/Resources/menubar-z-$state.pdf" "$ROOT/art/menubar-z-$state.svg"
done

echo "==> privileged helper binary (installed once to /Library/PrivilegedHelperTools by the app)"
cp "$BUILD/neversleep-helper" "$APP/Contents/Resources/neversleep-helper"

echo "==> ad-hoc codesign"
codesign --force --sign - "$APP" 2>/dev/null || true
echo "Done: $APP  — copy to /Applications and enjoy"
