#!/usr/bin/env bash
# SVG -> PNG(7 sizes) -> .icns on the Mac. Primary: qlmanage (built-in on every
# supported macOS); fallback: rsvg-convert from Homebrew if installed.
set -euo pipefail
# usage: make-iconset.sh <output.icns>   (run from anywhere; resolves via script dir)
ICNS_OUT="${1:?usage: make-iconset.sh <output.icns>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVG="$ROOT/art/neversleep-app-icon.svg"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ICONSET="$TMP/NeverSleep.iconset"; mkdir -p "$ICONSET"

rasterize() {  # $1 = target size (px), $2 = out png
  local size="$1" out="$2"
  if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert -w "$size" -h "$size" "$SVG" > "$out"
  else
    qlmanage -t -s "$size" -o "$TMP" "$SVG" >/dev/null 2>&1
    mv "$TMP/$(basename "$SVG").png" "$out"
  fi
}

for pair in 16 32 64 128 256 512 1024; do
  rasterize "$pair" "$TMP/raw_$pair.png"
done
cp "$TMP/raw_16.png"  "$ICONSET/icon_16x16.png"
cp "$TMP/raw_32.png"  "$ICONSET/icon_16x16@2x.png"
cp "$TMP/raw_32.png"  "$ICONSET/icon_32x32.png"
cp "$TMP/raw_64.png"  "$ICONSET/icon_32x32@2x.png"
cp "$TMP/raw_128.png" "$ICONSET/icon_128x128.png"
cp "$TMP/raw_256.png" "$ICONSET/icon_128x128@2x.png"
cp "$TMP/raw_256.png" "$ICONSET/icon_256x256.png"
cp "$TMP/raw_512.png" "$ICONSET/icon_256x256@2x.png"
cp "$TMP/raw_512.png" "$ICONSET/icon_512x512.png"
cp "$TMP/raw_1024.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$ICNS_OUT"
echo "icns written: $ICNS_OUT"
