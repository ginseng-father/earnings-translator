#!/bin/bash
# Builds EarningsTranslator and assembles build/EarningsTranslator.app.
# Ad-hoc signing changes the code signature on every rebuild, so macOS asks
# for audio-capture permission again after each build.
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c "$CONFIG" --product EarningsTranslator
BIN="$(swift build -c "$CONFIG" --show-bin-path)/EarningsTranslator"

APP="build/EarningsTranslator.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/EarningsTranslator"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"
