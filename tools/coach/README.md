# PrepSuite coach

The AI brain of PrepSuite: one small Deno HTTP service in `supabase/functions/coach/` that calls Anthropic or
Ollama. Audio never leaves the phone; the app sends the on-device transcript plus delivery numbers (pace,
pauses, fillers, loudness, pitch) and gets short JSON back. The same `index.ts` runs locally and as a Supabase
Edge Function.

## Run locally

```sh
tools/coach/run-local.sh                                         # foreground; Ctrl-C to stop
```

It listens on `0.0.0.0:8787` and answers only requests that carry its access token (header
`x-coach-token`). The first run creates a random token in `supabase/functions/.env` (git-ignored,
readable only by you) and prints the `flutter run` lines that pass it to the app. Without a token the
coach refuses to listen on a network address (set `HOST=127.0.0.1` for this computer only, or
`COACH_ALLOW_OPEN=1` to override). Rate limits apply: 20 requests a minute and 300 a day per client,
2,000 a day in total (`COACH_RATE_PER_MINUTE`, `COACH_RATE_PER_DAY`, `COACH_DAILY_LIMIT`). See
`SECURITY.md` at the repository root.

Point the app at:

- Android emulator: `http://10.0.2.2:8787`
- iOS simulator: `http://localhost:8787`
- Phone on the same Wi-Fi: `http://<Mac LAN IP>:8787` (`ipconfig getifaddr en0`)

Set `OLLAMA_MODEL` to use an Ollama model (including an Ollama cloud model), or set an Anthropic key. The
service returns `503 not_configured` when neither provider is configured. `COACH_MOCK=1` explicitly enables
free, deterministic, job-aware demo responses.

For example, with Ollama running on this computer:

```sh
COACH_MOCK=0 OLLAMA_MODEL=gemma4:31b-cloud tools/coach/run-local.sh
```

This model uses Ollama's cloud through the local Ollama app, so it needs internet and an Ollama sign-in.
It is not an offline language model. The service sends the transcript and numeric voice measurements;
it never uploads the recording. To use an installed local model instead, set `OLLAMA_MODEL` to its name.
The health reply reports the actual provider, selected model, and whether it uses cloud inference.

## Add an Anthropic key

1. Create an API key at console.anthropic.com (Settings > API keys) and make sure the account has credit.
2. Add it to `supabase/functions/.env` (git-ignored; `>>` keeps the access token already in there):
   ```sh
   echo 'ANTHROPIC_API_KEY=sk-ant-...' >> supabase/functions/.env && chmod 600 supabase/functions/.env
   ```
3. Restart the server. `curl -s -H "x-coach-token: $TOKEN" localhost:8787/health` should report `provider:"anthropic"` and
   `mock:false` (`TOKEN` is the `COACH_TOKEN` value in `supabase/functions/.env`; without it health shows only `ok`).

## Deploy to Supabase (later)

```sh
supabase secrets set ANTHROPIC_API_KEY=sk-ant-... COACH_TOKEN="$(openssl rand -hex 24)" --project-ref qtwhzseowgktmocsjwib
supabase functions deploy coach --project-ref qtwhzseowgktmocsjwib --no-verify-jwt --use-api
```

Endpoint: `https://qtwhzseowgktmocsjwib.supabase.co/functions/v1/coach` (health: `.../functions/v1/coach/health`).
`--no-verify-jwt` skips Supabase's own key check. The coach checks its own token instead and will not start
without the `COACH_TOKEN` secret. Build the app for it with `tools/release/build-android.sh`. A token can
be pulled out of a release app, so the rate limits and the daily ceiling bound the cost. Add per-person
sign-in before a public release.

## Smoke test

Run the complete real-provider flow with invented job and answer text:

```sh
COACH_TOKEN=<token> deno run --allow-net --allow-env tools/coach/smoke.ts http://127.0.0.1:8787
```

It checks health, generates five job questions, requests feedback on five answers, then requests tips,
last-minute notes, and reusable stories. It fails if the server is in demo mode. Each response is printed
for review. For a separate test server, use `PORT=8788` when starting the coach and pass that port here.

Individual requests (`TOKEN` is the `COACH_TOKEN` value in `supabase/functions/.env`):

```sh
curl -s -H "x-coach-token: $TOKEN" localhost:8787/health
curl -s -X POST localhost:8787/coach -H 'content-type: application/json' -H "x-coach-token: $TOKEN" \
  -d '{"action":"questions","job":"um I am going for like a barista job","count":3}'
curl -s -X POST localhost:8787/coach -H 'content-type: application/json' -H "x-coach-token: $TOKEN" \
  -d '{"action":"feedback","job":"barista","question":"Why this job?","transcript":"We just worked hard as a team and it went fine.","delivery":null}'
```

## Tests

```sh
deno test --node-modules-dir=none supabase/functions/coach/  # injected providers: no network or key
```

## Notes for the app

- Actions: `questions`, `feedback`, `wrapup` on `POST /coach` (also `/` and `/functions/v1/coach`). Every success
  includes `"mock": true|false`.
- Errors are `{"error":{"code","message"}}`: `bad_request` 400 (404/405 for a wrong path or method, 415 when
  the body is not `application/json`), `unauthorized` 401 (missing or wrong access token),
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
- Claude runs with adaptive thinking at a per-route effort (`low` for questions, `medium` for feedback and
  notes). Thinking counts against `max_tokens`, so each call gets 12,000 tokens of room on top of the reply.
  If a safety classifier declines a request, `fallbacks: "default"` (beta `server-side-fallback-2026-07-01`)
  re-runs it on the model Anthropic recommends, and the log's `served_by` shows which model answered.
- The job can include the kind of interview ("barista, group interview"); questions and `job_title` follow it.
