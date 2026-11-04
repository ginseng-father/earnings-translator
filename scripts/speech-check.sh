#!/bin/bash
# End-to-end check of on-device transcription from inside the app bundle.
# Speech recognition needs the app (not the terminal) to be the responsible
# process, so it is launched with `open`. The first run asks for permission.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build-app.sh debug >/dev/null
AUDIO="${TMPDIR:-/tmp}/et-say.aiff"
OUT="${TMPDIR:-/tmp}/et-speech-check.txt"
say -v Samantha -o "$AUDIO" "Revenue was 94.9 billion dollars, up 6 percent year over year."
: > "$OUT"
open -W -n --stdout "$OUT" --stderr "$OUT" build/EarningsTranslator.app --args --transcribe-file "$AUDIO"
cat "$OUT"
grep -q "FINAL.*94.9" "$OUT" && grep -q "FINAL.*6" "$OUT" && echo "speech-check: PASS"
