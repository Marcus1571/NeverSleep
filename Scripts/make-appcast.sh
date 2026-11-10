#!/bin/sh
# Regenerates appcast.xml for the given version from a built, signed DMG.
#
# Usage: scripts/make-appcast.sh <version> [dmg]
#   dmg defaults to .build/dist/NeverSleep-<version>.dmg (from make-dmg.sh).
#
# The enclosure URL points at the GitHub Release asset, which the release flow
# must have published by the time the appcast commit is pushed (push order:
# tag + GitHub Release with the DMG asset first, then `git push origin main`).
#
# The EdDSA signature uses Sparkle's private key stored in this machine's
# login keychain (generate_keys) — the same key diskled-plus uses (same
# operator, same keychain); the matching public key is baked into the app's
# Info.plist (SUPublicEDKey), so only DMGs signed with that key pass.
set -eu

cd "$(cd "$(dirname "$0")/.." && pwd)"

VERSION="${1:?Usage: make-appcast.sh <version> [dmg]}"
DMG="${2:-.build/dist/NeverSleep-${VERSION}.dmg}"
SIGN_TOOL=".build/artifacts/sparkle/Sparkle/bin/sign_update"
APPCAST="appcast.xml"
FEED_URL="https://raw.githubusercontent.com/Marcus1571/NeverSleep/main/appcast.xml"

[ -f "$DMG" ] || { echo "DMG missing: $DMG (run make-dmg.sh first)" >&2; exit 1; }

DMG_LENGTH="$(stat -f %z "$DMG")"
SIGN_LINE="$("$SIGN_TOOL" "$DMG")"
SIGNATURE="$(echo "$SIGN_LINE" | sed -n 's/^sparkle:edSignature="\([^"]*\)".*/\1/p')"
SIGNED_LENGTH="$(echo "$SIGN_LINE" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"
if [ -z "$SIGNATURE" ] || [ -z "$SIGNED_LENGTH" ] || [ "$SIGNED_LENGTH" != "$DMG_LENGTH" ]; then
    echo "sign_update output not understood: $SIGN_LINE" >&2
    exit 1
fi
PUB_DATE="$(LC_ALL=en_US.UTF-8 date -u +"%a, %d %b %Y %H:%M:%S GMT")"
ENCLOSURE_URL="https://github.com/Marcus1571/NeverSleep/releases/download/v${VERSION}/NeverSleep-${VERSION}.dmg"
NUMERIC_VERSION="$(echo "$VERSION" | awk -F. '{print $1*10000+$2*100+$3}')"

cat > "$APPCAST" <<EOF
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>NeverSleep</title>
    <link>${FEED_URL}</link>
    <description>Most recent NeverSleep releases.</description>
    <language>en</language>
    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:releaseNotesLink>https://github.com/Marcus1571/NeverSleep/releases/tag/v${VERSION}</sparkle:releaseNotesLink>
      <enclosure url="${ENCLOSURE_URL}"
                 sparkle:version="${NUMERIC_VERSION}"
                 sparkle:shortVersionString="${VERSION}"
                 sparkle:edSignature="${SIGNATURE}"
                 length="${DMG_LENGTH}"
                 type="application/octet-stream" />
      <sparkle:minimumSystemVersion>11.0</sparkle:minimumSystemVersion>
    </item>
  </channel>
</rss>
EOF

echo "Wrote $APPCAST (version ${VERSION}, build ${NUMERIC_VERSION})"
echo "$SIGN_LINE"
