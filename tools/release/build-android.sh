#!/usr/bin/env bash
# Build a release app bundle for Google Play:
#   COACH_URL=https://<project>.supabase.co/functions/v1/coach COACH_TOKEN=<token> tools/release/build-android.sh
# The Dart code is obfuscated and its debug symbols are kept out of the app (in build/symbols,
# which turns crash reports back into readable ones: keep it, never commit it). The coach must be
# https; release builds refuse plain http.
set -euo pipefail

: "${COACH_URL:?Set COACH_URL to the https address of the coach}"
: "${COACH_TOKEN:?Set COACH_TOKEN to the coach access token (16 characters or more)}"
case "$COACH_URL" in
  https://*) ;;
  *) echo "COACH_URL must start with https://" >&2; exit 1 ;;
esac
if [[ ${#COACH_TOKEN} -lt 16 ]]; then
  echo "COACH_TOKEN must be at least 16 characters." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols \
  --dart-define=COACH_URL="$COACH_URL" --dart-define=COACH_TOKEN="$COACH_TOKEN"
echo "Built build/app/outputs/bundle/release/app-release.aab. Keep build/symbols for crash reports."
