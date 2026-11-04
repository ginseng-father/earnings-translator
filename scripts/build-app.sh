#!/bin/bash
# Builds EarningsTranslator and assembles build/EarningsTranslator.app.
# Ad-hoc signed, with a designated requirement pinned to the bundle id so that
# macOS keeps the speech/audio permissions across rebuilds (the default ad-hoc
# requirement is the build's hash, which changes every time).
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c "$CONFIG" --product EarningsTranslator
BIN="$(swift build -c "$CONFIG" --show-bin-path)/EarningsTranslator"

APP="build/EarningsTranslator.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/EarningsTranslator"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"  # regenerate: swift scripts/make-icon.swift
codesign --force --sign - --identifier local.earningstranslator \
    --requirements '=designated => identifier "local.earningstranslator"' "$APP"
echo "Built $APP"
