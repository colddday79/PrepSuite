#!/usr/bin/env bash
# Start the PrepSuite coach on 0.0.0.0:8787.
#   Android emulator:        http://10.0.2.2:8787
#   iOS simulator:           http://localhost:8787
#   Phone on the same Wi-Fi: http://<this Mac's LAN IP>:8787
# Set OLLAMA_MODEL (for example, gemma4:31b-cloud) to use the Ollama app, or
# ANTHROPIC_API_KEY/ANTHROPIC_AUTH_TOKEN for Anthropic. COACH_MOCK=1 enables
# deterministic demo responses explicitly.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT/supabase/functions/.env"

if ! command -v deno >/dev/null 2>&1; then
  echo "Deno is not installed. Install it with: brew install deno" >&2
  exit 1
fi

export PORT="${PORT:-8787}"
export HOST="${HOST:-0.0.0.0}"

args=(run --no-prompt --node-modules-dir=none --allow-net --allow-env)
if [[ -f "$ENV_FILE" ]]; then
  args+=("--env-file=$ENV_FILE")
  echo "Using supabase/functions/.env"
fi

LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || true)"
echo "Android emulator: http://10.0.2.2:$PORT  iOS simulator: http://localhost:$PORT${LAN_IP:+  phone on Wi-Fi: http://$LAN_IP:$PORT}"

cd "$ROOT/supabase/functions/coach"
exec deno "${args[@]}" index.ts
