#!/bin/bash
# Runs `swift test` with the swift-testing macro plugin path spelled out.
# Without Xcode, incremental builds under the Command Line Tools sometimes
# drop this path and every @Test fails with "plugin for module 'TestingMacros'
# not found".
set -euo pipefail
cd "$(dirname "$0")/.."
PLUGINS="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
