# PrepSuite coach

The AI brain of PrepSuite: one small Deno HTTP service in `supabase/functions/coach/` that calls Anthropic or
Ollama. Audio never leaves the phone; the app sends the on-device transcript plus delivery numbers (pace,
pauses, fillers, loudness, pitch) and gets short JSON back. The same `index.ts` runs locally and as a Supabase
Edge Function.

## Run locally

```sh
tools/coach/run-local.sh                                         # foreground; Ctrl-C to stop
```

It listens on `0.0.0.0:8787`. Point the app at:

- Android emulator: `http://10.0.2.2:8787`
- iOS simulator: `http://localhost:8787`
- Phone on the same Wi-Fi: `http://<Mac LAN IP>:8787` (`ipconfig getifaddr en0`), or use `tools/run-phone.sh`

Real AI is the default. When nothing is configured (no `COACH_MOCK=1`, no `OLLAMA_MODEL`, and no
`ANTHROPIC_API_KEY`/`ANTHROPIC_AUTH_TOKEN` in the environment or `supabase/functions/.env`), the script asks
the local Ollama app for its models (2 second timeout), picks `gemma4:31b-cloud` when installed or else the
first chat model, and prints which one it uses. If Ollama is not running and nothing else is set, it prints a
one-line warning: requests get `503 not_configured` until you open the Ollama app, set `OLLAMA_MODEL`, or add
an Anthropic key. `COACH_MOCK=1` explicitly enables free, deterministic, job-aware sample answers; the script
says so when it starts, and every reply carries `"mock": true`.

To choose the model yourself:

```sh
COACH_MOCK=0 OLLAMA_MODEL=gemma4:31b-cloud tools/coach/run-local.sh
```

This model uses Ollama's cloud through the local Ollama app, so it needs internet and an Ollama sign-in.
It is not an offline language model. The service sends the transcript and numeric voice measurements;
it never uploads the recording. To use an installed local model instead, set `OLLAMA_MODEL` to its name.
The health reply reports the actual provider, selected model, and whether it uses cloud inference.

## Run the app on a phone

```sh
tools/run-phone.sh              # extra arguments go to flutter run, e.g. -d <device id>
```

The phone must be on the same Wi-Fi as this Mac: it reaches the coach at `http://<Mac LAN IP>:8787/coach`.
The script finds the LAN IP (`en0`, then `en1`), starts `tools/coach/run-local.sh` in the background when
nothing is listening on port 8787 (it prints the log path, in the system temp folder, and leaves the coach
running for the next run), shows the coach's health, then runs
`flutter run --dart-define=COACH_URL=http://<LAN IP>:8787/coach`. Use a debug build (the default): release
builds block plain http. On iPhone, allow local network access when asked. If the phone cannot connect,
check that both devices are on the same Wi-Fi and that the macOS firewall allows incoming connections to Deno.

## Add an Anthropic key

1. Create an API key at console.anthropic.com (Settings > API keys) and make sure the account has credit.
2. Put it in `supabase/functions/.env` (gitignored):
   ```sh
   echo 'ANTHROPIC_API_KEY=sk-ant-...' > supabase/functions/.env
   ```
3. Restart the server. `curl -s localhost:8787/health` should report `provider:"anthropic"` and `mock:false`.

## Deploy to Supabase (later)

```sh
supabase secrets set ANTHROPIC_API_KEY=sk-ant-... --project-ref qtwhzseowgktmocsjwib
supabase functions deploy coach --project-ref qtwhzseowgktmocsjwib --no-verify-jwt --use-api
```

Endpoint: `https://qtwhzseowgktmocsjwib.supabase.co/functions/v1/coach` (health: `.../functions/v1/coach/health`).
`--no-verify-jwt` makes it public: anyone with the URL can spend Anthropic credit, so add app auth or rate
limiting before a public release.

## Smoke test

Run the complete real-provider flow with invented job and answer text:

```sh
deno run --allow-net tools/coach/smoke.ts http://127.0.0.1:8787
```

It checks health, generates five job questions, requests feedback on five answers, asks the coach two
questions about the first answer, then requests tips, last-minute notes, and reusable stories. It fails if
the server is in demo mode. Each response is printed for review. For a separate test server, use
`PORT=8788` when starting the coach and pass that port here.

Individual requests:

```sh
curl -s localhost:8787/health
curl -s -X POST localhost:8787/coach -H 'content-type: application/json' \
  -d '{"action":"questions","job":"um I am going for like a barista job","count":3}'
curl -s -X POST localhost:8787/coach -H 'content-type: application/json' \
  -d '{"action":"feedback","job":"barista","question":"Why this job?","transcript":"We just worked hard as a team and it went fine.","delivery":null}'
curl -s -X POST localhost:8787/coach -H 'content-type: application/json' \
  -d '{"action":"ask","job":"barista","user_question":"How long should my answer be?","question":"Why this job?"}'
```

## Tests

```sh
deno test --node-modules-dir=none supabase/functions/coach/  # injected providers: no network or key
```

## Notes for the app

- Actions: `questions`, `feedback`, `wrapup`, `ask` on `POST /coach` (also `/` and `/functions/v1/coach`). Every
  success includes `"mock": true|false`.
- `ask` answers the person's own question during practice and the app reads the reply aloud. Body:
  `user_question` (required, at most 500 characters), and optional `job` (300), `question` (the interview
  question on screen, 400), `answer` (their latest transcript, 6000) and `feedback`
  (`{"headline","problem","fix"}`, each optional, 1000). Reply: `{"answer": string, "mock": bool}`, 2 to 4
  plain spoken sentences with no markdown, lists, links or em dashes, capped at 110 words. It never invents
  facts about the employer, pay or the person's experience, and gives no scores or predictions.
- Errors are `{"error":{"code","message"}}`: `bad_request` 400 (404/405 for a wrong path or method),
  `rate_limited` 429, `upstream` 502/503/504, `not_configured` 503 (key missing, invalid, or out of credit).
- `count` defaults to 5. In feedback, `delivery` may be `null` or omitted, and `pitch_hz_mean`,
  `pitch_semitone_sd` and `monotone` may be `null`. In wrap-up, each answer's `headline`, `problem` and
  `delivery` are optional. Unknown fields are ignored.
- `evidence` is a verified transcript quote or `""`. Unverifiable provider quotes are rejected, never
  silently turned into invented feedback. Wrap-up stories are tied to source answer numbers and verified
  quotes; the HTTP `stories_to_use` field remains a list of strings.
- Feedback identifies one content problem, one practical change, and a specific strength. It distinguishes
  motivation questions, hypothetical scenarios, and questions asking for a past example.
- Voice feedback is computed from supplied measurements, including pace, pauses, fillers, volume changes,
  and pitch variation when available. These observations do not establish emotion, confidence, personality,
  honesty, or employability. Typed answers receive no tone judgement.
- Live calls take a few seconds (feedback longest). Give the HTTP client a 120 s timeout and show progress.
- Provider settings: structured JSON outputs, short response limits, and strict server-side validation of
  quotes, lists, and delivery measurements. The health response identifies the active provider and model.
