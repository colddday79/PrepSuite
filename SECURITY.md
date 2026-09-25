# Security

## Reporting a problem

Please don't open a public issue for a security problem. Use **Report a vulnerability** on this
repository's **Security** tab (GitHub's private vulnerability reporting) and include the steps to
reproduce it.

## How PrepSuite protects people's data

- **Audio stays on the phone.** Speech is turned into text on the device, and each recording is
  deleted right after transcription.
- **The coach gets text, not audio.** It receives the job, the question, the answer's text and voice
  measurements (pace, pauses, fillers, loudness, pitch). It stores nothing and never logs
  transcripts, prompts or keys.
- **Saved practice stays on the phone.** Only the latest practice is saved, on the device. Android
  backups and device-to-device transfers are turned off for the app's data
  (`android/app/src/main/AndroidManifest.xml`, `res/xml/data_extraction_rules.xml`), and the person
  can delete it in Settings.
- **Encrypted connections only in release builds.** Android's `network_security_config.xml` blocks
  plain http and trusts only the phone's built-in certificate authorities, iOS App Transport
  Security blocks plain http, and `CoachConfig.allowed` refuses a non-https coach. Plain http is
  allowed only in debug builds, for a coach on the developer's computer.
- **Release builds are obfuscated.** `tools/release/build-android.sh` builds with `--obfuscate` and
  keeps the debug symbols out of the app.

## How the coach service is protected

- **Access token.** The coach answers only requests that carry its token in `x-coach-token`
  (compared in constant time). It refuses to listen on a network address without one, and a
  Supabase deployment without the `COACH_TOKEN` secret fails to start. `tools/coach/run-local.sh`
  creates a random token in `supabase/functions/.env` (git-ignored, readable only by you).
- **Rate limits.** Each client gets 20 requests a minute and 300 a day, and everyone together gets
  2,000 a day, a ceiling on AI spend even if the token leaks. Ten wrong tokens lock an address out
  for ten minutes. Tune them with `COACH_RATE_PER_MINUTE`, `COACH_RATE_PER_DAY` and
  `COACH_DAILY_LIMIT`.
- **Strict input.** Requests must be JSON, so a web page can't post to the coach without the browser
  asking first. Bodies are capped at 200 KB, every field has a length limit, and the person's words
  go to the AI as data inside delimited tags, never as instructions. AI replies are validated before
  they are returned, and any quote must appear word for word in the answer.
- **Response headers.** `Cache-Control: no-store`, `X-Content-Type-Options: nosniff`, a deny-all
  content security policy, and no CORS unless `COACH_CORS_ORIGIN` names a trusted origin.
- **Secrets stay out of git.** API keys and the token live only in `supabase/functions/.env` or in
  Supabase secrets. CI scans every commit for leaked secrets with gitleaks, pins its actions to
  exact commits, and runs the coach's security tests (`supabase/functions/coach/security_test.ts`).
  Dependabot proposes dependency updates weekly.

**Known limits:** someone determined can pull the token out of a release build. The token keeps out
casual abuse, and the rate limits and the daily ceiling bound what a leaked token can cost. On
Supabase, limits are counted in each running instance's memory and per-client limits go by the
forwarded client address, so treat the daily ceiling and your Anthropic spend limit as the hard stop.
Before a public release, add per-person sign-in (Supabase anonymous auth) and keep the counts in the
database, so the limits apply per person.

## Owner checklist

These settings live in accounts only the owner can change.

**GitHub** (this repository's settings):
- [ ] Security > Advisories: turn on **Private vulnerability reporting**.
- [ ] Security > Code security: turn on **Secret scanning** with **Push protection**, **Dependabot
      alerts**, **Dependabot security updates** and **CodeQL** (default setup).
- [ ] Settings > Branches: protect `main` so changes need a pull request and a green `ci` check.
- [ ] Turn on two-factor authentication for the account, and consider making the repository private.

**Anthropic console:**
- [ ] Use a separate API key for PrepSuite and set a monthly spend limit. If the key ever leaks,
      delete it and make a new one.

**Supabase** (before deploying the coach):
- [ ] Set secrets with `supabase secrets set ANTHROPIC_API_KEY=... COACH_TOKEN=...`, never in code.
- [ ] Turn on Row Level Security for every table you add.

**Google Play** (before the first release):
- [ ] Create an upload key. Keep it and `android/key.properties` out of git (both are ignored), and
      use Play App Signing. Release builds are still signed with the debug key until this is set up
      in `android/app/build.gradle.kts`.
