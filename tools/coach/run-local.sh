#!/usr/bin/env bash
# Start the PrepSuite coach on 0.0.0.0:8787.
#   Android emulator:        http://10.0.2.2:8787
#   iOS simulator:           http://localhost:8787
#   Phone on the same Wi-Fi: http://<this Mac's LAN IP>:8787
# Set OLLAMA_MODEL (for example, gemma4:31b-cloud) to use the Ollama app, or
# ANTHROPIC_API_KEY/ANTHROPIC_AUTH_TOKEN for Anthropic. COACH_MOCK=1 enables
# deterministic demo responses explicitly.
#
# The coach spends your AI credit, so it only answers apps that send its access
# token. The first run creates one in supabase/functions/.env (never committed)
# and prints the flutter run command that passes it to the app.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT/supabase/functions/.env"

if ! command -v deno >/dev/null 2>&1; then
  echo "Deno is not installed. Install it with: brew install deno" >&2
  exit 1
fi

export PORT="${PORT:-8787}"
export HOST="${HOST:-0.0.0.0}"

if [[ -z "${COACH_TOKEN:-}" ]] && ! grep -q '^COACH_TOKEN=' "$ENV_FILE" 2>/dev/null; then
  (umask 077 && echo "COACH_TOKEN=$(openssl rand -hex 24 2>/dev/null || od -An -N24 -tx1 /dev/urandom | tr -d ' \n')" >> "$ENV_FILE")
  echo "Created an access token in supabase/functions/.env"
fi
TOKEN="${COACH_TOKEN:-$(grep '^COACH_TOKEN=' "$ENV_FILE" | tail -1 | cut -d= -f2-)}"

args=(run --no-prompt --node-modules-dir=none --allow-net --allow-env)
if [[ -f "$ENV_FILE" ]]; then
  chmod 600 "$ENV_FILE"
  args+=("--env-file=$ENV_FILE")
  echo "Using supabase/functions/.env"
fi

LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || true)"
echo
echo "Run the app against this coach:"
echo "  Emulator: flutter run --dart-define=COACH_TOKEN=$TOKEN"
if [[ -n "$LAN_IP" ]]; then
  echo "  Phone:    flutter run -d <phone-id> --dart-define=COACH_URL=http://$LAN_IP:$PORT/coach --dart-define=COACH_TOKEN=$TOKEN"
fi
echo

cd "$ROOT/supabase/functions/coach"
exec deno "${args[@]}" index.ts
