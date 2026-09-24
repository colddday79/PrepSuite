# PrepSuite coach

The AI brain of PrepSuite: one small Deno HTTP service in `supabase/functions/coach/` that calls Claude
(`claude-opus-5`). Audio never leaves the phone; the app sends the on-device transcript plus delivery numbers
(pace, pauses, fillers, loudness, pitch) and gets short JSON back. The same `index.ts` runs locally and as a
Supabase Edge Function.

## Run locally

```sh
tools/coach/run-local.sh                                           # foreground
nohup tools/coach/run-local.sh > /tmp/prepsuite-coach.log 2>&1 &   # background
kill $(lsof -ti tcp:8787)                                          # stop
```

It listens on `0.0.0.0:8787`. Point the app at:

- Android emulator: `http://10.0.2.2:8787`
- iOS simulator: `http://localhost:8787`
- Phone on the same Wi-Fi: `http://<Mac LAN IP>:8787` (`ipconfig getifaddr en0`)

With no Anthropic key the service runs in **mock mode**: free, deterministic, job-aware answers with
`"mock": true`. `COACH_MOCK=1` forces mock mode even when a key is set.

## Add the Anthropic key

1. Create an API key at console.anthropic.com (Settings > API keys) and make sure the account has credit.
2. Put it in `supabase/functions/.env` (gitignored):
   ```sh
   echo 'ANTHROPIC_API_KEY=sk-ant-...' > supabase/functions/.env
   ```
3. Restart the server. `curl -s localhost:8787/health` should now say `"mock":false`.

## Deploy to Supabase (later)

```sh
supabase secrets set ANTHROPIC_API_KEY=sk-ant-... --project-ref qtwhzseowgktmocsjwib
supabase functions deploy coach --project-ref qtwhzseowgktmocsjwib --no-verify-jwt --use-api
```

Endpoint: `https://qtwhzseowgktmocsjwib.supabase.co/functions/v1/coach` (health: `.../functions/v1/coach/health`).
`--no-verify-jwt` makes it public: anyone with the URL can spend Anthropic credit, so add app auth or rate
limiting before a public release.

## Smoke test

```sh
curl -s localhost:8787/health
curl -s -X POST localhost:8787/coach -H 'content-type: application/json' \
  -d '{"action":"questions","job":"um I am going for like a barista job","count":3}'
curl -s -X POST localhost:8787/coach -H 'content-type: application/json' \
  -d '{"action":"feedback","job":"barista","question":"Why this job?","transcript":"We just worked hard as a team and it went fine.","delivery":null}'
```

## Tests

```sh
deno test supabase/functions/coach/   # fake Claude client: no network, no key
```

## Notes for the app

- Actions: `questions`, `feedback`, `wrapup` on `POST /coach` (also `/` and `/functions/v1/coach`). Every success
  includes `"mock": true|false`.
- Errors are `{"error":{"code","message"}}`: `bad_request` 400 (404/405 for a wrong path or method),
  `rate_limited` 429, `upstream` 502/503/504, `not_configured` 503 (key missing, invalid, or out of credit).
- `count` defaults to 5. In feedback, `delivery` may be `null` or omitted, and `pitch_hz_mean`,
  `pitch_semitone_sd` and `monotone` may be `null`. In wrap-up, each answer's `headline`, `problem` and
  `delivery` are optional. Unknown fields are ignored.
- `evidence` is always an exact quote from the transcript or `""` (the server drops quotes it cannot find).
- Live calls take a few seconds (feedback longest). Give the HTTP client a 120 s timeout and show progress.
- Claude settings: adaptive thinking, structured JSON outputs, effort `low` for questions and `medium` for
  feedback and wrap-up, and server-side refusal fallbacks (`fallbacks: "default"`).
