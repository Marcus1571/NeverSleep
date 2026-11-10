#!/bin/sh
# Builds a distribution DMG: .build/dist/NeverSleep-<version>.dmg
#
# Usage: scripts/make-dmg.sh [version] [identity]
#   version   — defaults to the latest CHANGELOG heading.
#   identity  — passed through to make-app.sh ("Developer ID" for the
#               notarizable build; omit for ad-hoc).
#
# Notarization runs when the notary keychain profile exists. The profile is
# shared across the operator's menu-bar apps (same Apple ID / team):
# "diskledplus-notary", created during diskled-plus (see that repo's AGENTS.md).
# Override with NOTARY_PROFILE=<name> if that changes. When no profile exists
# the DMG is still built (unsigned-DMG is fine for local use only — Gatekeeper
# blocks unsigned downloads on other machines).
set -eu

cd "$(cd "$(dirname "$0")/.." && pwd)"

VERSION="${1:-$(grep -m1 -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' CHANGELOG.md | tr -d '[]' | sed 's/^## //')}"
IDENTITY="${2:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-diskledplus-notary}"
STAGING=".build/dmg-staging"
DMG=".build/dist/NeverSleep-${VERSION}.dmg"

scripts/make-app.sh "$VERSION" "$IDENTITY"

rm -rf "$STAGING"
mkdir -p "$STAGING" .build/dist
cp -R .build/app/NeverSleep.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "NeverSleep" -srcfolder "$STAGING" -ov -format UDZO "$DMG"

# The DMG container itself is notarized (Apple best practice).
if [ -n "$IDENTITY" ]; then
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
fi

set +e
SUBMIT_OUTPUT="$(xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)"
SUBMIT_STATUS=$?
set -e
if [ $SUBMIT_STATUS -eq 0 ]; then
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    echo "Notarized + stapled: $DMG"
elif echo "$SUBMIT_OUTPUT" | grep -qi "keychain\|credential"; then
    echo "WARNING: notary keychain profile '$NOTARY_PROFILE' not found."
    echo "DMG built but NOT notarized: $DMG"
    echo "Gatekeeper will block this on machines other than the build host."
    echo "Run: xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <your Apple ID> --password <app-specific password> --team-id <TEAMID>"
else
    echo "Notarization submit failed:"
    echo "$SUBMIT_OUTPUT"
    exit 1
fi
