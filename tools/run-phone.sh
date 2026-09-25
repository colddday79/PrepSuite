#!/usr/bin/env bash
# Run PrepSuite on a connected phone, talking to the coach on this Mac over Wi-Fi.
# The phone must be on the same Wi-Fi as this Mac. Starts the coach in the
# background when nothing is listening on port 8787, then runs
#   flutter run --dart-define=COACH_URL=http://<this Mac's LAN IP>:8787/coach
# Extra arguments go to flutter run, for example: tools/run-phone.sh -d <device id>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT=8787

LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
if [[ -z "$LAN_IP" ]]; then
  echo "No Wi-Fi or LAN address found on en0 or en1, so the phone cannot reach the coach. Connect this Mac to the same Wi-Fi as the phone and run this again." >&2
  exit 1
fi

if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t >/dev/null 2>&1; then
  echo "Coach already running on port $PORT."
else
  LOG="${TMPDIR:-/tmp}"
  LOG="${LOG%/}/prepsuite-coach.log"
  PORT="$PORT" nohup "$ROOT/tools/coach/run-local.sh" >"$LOG" 2>&1 &
  echo "Started the coach in the background (pid $!). Log: $LOG"
  for _ in $(seq 1 20); do
    curl -s -m 1 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && break
    sleep 0.5
  done
fi

HEALTH="$(curl -s -m 3 "http://127.0.0.1:$PORT/health" 2>/dev/null || true)"
case "$HEALTH" in
  *'"mock":true'*) echo "Warning: the coach on port $PORT gives sample answers (COACH_MOCK=1), not real AI." >&2 ;;
  *'"ok":true'*) echo "Coach: $HEALTH" ;;
  *) echo "Warning: the coach on port $PORT is not ready (${HEALTH:-no reply}). See the log or tools/coach/README.md." >&2 ;;
esac

COACH_URL="http://$LAN_IP:$PORT/coach"
echo "The phone will use the coach at $COACH_URL (it must be on the same Wi-Fi as this Mac)."
cd "$ROOT"
exec flutter run --dart-define=COACH_URL="$COACH_URL" "$@"
