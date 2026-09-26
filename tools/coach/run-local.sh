#!/usr/bin/env bash
# Start the PrepSuite coach on 0.0.0.0:8787.
#   Android emulator:        http://10.0.2.2:8787
#   iOS simulator:           http://localhost:8787
#   Phone on the same Wi-Fi: http://<this Mac's LAN IP>:8787 (or use tools/run-phone.sh)
# Real AI by default: with nothing configured, it uses a model from the local
# Ollama app (gemma4:31b-cloud when installed). Set OLLAMA_MODEL to pick an
# Ollama model, or ANTHROPIC_API_KEY/ANTHROPIC_AUTH_TOKEN (in the environment or
# supabase/functions/.env) for Anthropic. COACH_MOCK=1 enables deterministic
# sample answers explicitly.
#
# The coach spends your AI credit, so it only answers apps that send its access
# token. The first run creates one in supabase/functions/.env (never committed)
# and prints the flutter run command that passes it to the app.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT/supabase/functions/.env"
PREFERRED_OLLAMA_MODEL="gemma4:31b-cloud"

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

# A setting as the server will see it: the environment wins, then the .env file.
setting() {
  local value="${!1:-}"
  if [[ -z "$value" && -f "$ENV_FILE" ]]; then
    value="$(sed -nE "s/^[[:space:]]*(export[[:space:]]+)?$1[[:space:]]*=[[:space:]]*//p" "$ENV_FILE" | tail -n 1 || true)"
    value="${value%$'\r'}"
    value="${value%%[[:space:]]#*}"
    value="${value#[\"\']}"
    value="${value%[\"\']}"
  fi
  printf '%s' "$value"
}

# Prints the Ollama model to use (the preferred one, else the first chat model), or nothing
# when the Ollama app is not running. Never fails.
detect_ollama_model() {
  PROBE_URL="$(setting OLLAMA_URL)" PREFERRED="$PREFERRED_OLLAMA_MODEL" deno eval '
    const base = Deno.env.get("PROBE_URL") || "http://127.0.0.1:11434";
    try {
      const res = await fetch(new URL("/api/tags", base), { signal: AbortSignal.timeout(2000) });
      const body = res.ok ? await res.json() : null;
      const names = (Array.isArray(body?.models) ? body.models : [])
        .filter((m) => !Array.isArray(m?.capabilities) || m.capabilities.includes("completion"))
        .map((m) => String(m?.name ?? m?.model ?? "").trim())
        .filter((name) => /^[\w.:\/-]+$/.test(name));
      const preferred = Deno.env.get("PREFERRED");
      const pick = names.includes(preferred) ? preferred : names[0];
      if (pick) console.log(pick);
    } catch {
      // Not running, not reachable, or not Ollama: fall through to the warning.
    }
  ' 2>/dev/null || true
}

if [[ "$(setting COACH_MOCK)" == "1" ]]; then
  echo "Sample mode (COACH_MOCK=1): answers are canned examples, not real AI."
elif [[ -z "$(setting OLLAMA_MODEL)" && -z "$(setting ANTHROPIC_API_KEY)" && -z "$(setting ANTHROPIC_AUTH_TOKEN)" ]]; then
  detected="$(detect_ollama_model)"
  if [[ -n "$detected" ]]; then
    export OLLAMA_MODEL="$detected"
    echo "Real AI: using Ollama model $OLLAMA_MODEL from the Ollama app (set OLLAMA_MODEL to pick another)."
  else
    echo "Warning: no AI provider found, so requests will get 503 until one is configured. Fix: open the Ollama app and sign in, or set OLLAMA_MODEL, or put ANTHROPIC_API_KEY in supabase/functions/.env (COACH_MOCK=1 gives sample answers)." >&2
  fi
fi

LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
echo "Android emulator: http://10.0.2.2:$PORT  iOS simulator: http://localhost:$PORT${LAN_IP:+  phone on Wi-Fi: http://$LAN_IP:$PORT}"
echo
echo "Run the app against this coach:"
echo "  Emulator: flutter run --dart-define=COACH_TOKEN=$TOKEN"
if [[ -n "$LAN_IP" ]]; then
  echo "  Phone:    tools/run-phone.sh -d <phone-id>   (passes the coach address and token)"
fi
echo

cd "$ROOT/supabase/functions/coach"
exec deno "${args[@]}" index.ts
