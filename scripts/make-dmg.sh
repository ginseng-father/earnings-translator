#!/bin/bash
# Builds a release app and packs it into dist/EarningsTranslator-<version>.dmg
# together with the Korean install guide and an Applications shortcut.
# The app is ad-hoc signed and not notarized: recipients must allow it once
# (see packaging/설치 안내.txt).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
scripts/build-app.sh release

STAGING="$(mktemp -d)"
trap '/bin/rm -rf "$STAGING"' EXIT
cp -R build/EarningsTranslator.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cp "packaging/설치 안내.txt" "$STAGING/"

mkdir -p dist
DMG="dist/EarningsTranslator-$VERSION.dmg"
/bin/rm -f "$DMG"
hdiutil create -volname "EarningsTranslator $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
echo "Built $DMG"
