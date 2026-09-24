# PrepSuite baseline: build plan

## Context
You want the baseline of PrepSuite, the interview-practice app described in `INTERVIEW-APP-PRD.md`, running on the Android emulator. Code goes to GitHub (`jungwooshim1212/PrepSuite`) and the backend is Supabase.

**What "baseline" means here:**
- The hard logic is done properly now: auth, checkout, data filtering, session state and recovery, deletion, quotas.
- The screens are a working skeleton.
- The voice screen gets a premium visual.
- The real voice and AI providers come later. Until then they sit behind interfaces with fake stand-ins, so every flow still runs end to end.
- If more than 50% of your usage is left after all that, a Blender-made 3D assistant.
- Hard requirement: the app must not look vibecoded.

**Your decisions (from the questions):**
- **Checkout:** build the backend plus a fake provider now; plug in real Play Billing later.
- **Sign-in:** anonymous first, with upgrade by email code or Google.
- **Supabase:** `qtwhzseowgktmocsjwib` is the dev project now; create a separate prod project before the pilot.
- **3D:** Blender Cycles renders plus a live shader layer on top.

**Where this goes beyond the PRD (at your request):**
- **Auth:** implemented as lazy anonymous sign-in. A1 (no account needed) still holds.
- **Billing:** built only as a ledger plus a fake provider.
- **Content stays on the phone:** no sync, and no audio upload.

## Environment facts (checked)
- **Repo:** `/Users/macintosh/Documents/PrepSuite` has 1 commit and a CLI-generated `supabase/config.toml`, with anonymous sign-ins and manual linking both off.
- **GitHub:** Free private repo, so branch protection and secret scanning aren't available. `gh` is logged in with repo and workflow scopes.
- **Toolchain:**
  - Android Studio 2026.1 with JBR 21. System `java` is 8, so `JAVA_HOME` must point at the JBR.
  - SDK platforms go up to 36.1. Android 37 needs a `sdkmanager` install.
- **Emulator:** Pixel_10_Pro_XL, API 37.1 with Play Store, arm64, 16 KB pages, running on the host GPU.
- **Not installed:** Supabase CLI, Deno, Docker, Blender, ffmpeg. There's no Docker, so no local Supabase stack; we deploy with `--use-api` against the dev project.

## Stack (versions verified 2026-09-23)
- **Build:**
  - Gradle 9.7.1 and **AGP 9.3.3** (your Studio can't sync 9.4 yet). AGP 9 builds Kotlin in, so don't apply the `kotlin-android` plugin.
  - Kotlin 2.4.20, KSP 2.3.12.
  - compileSdk and targetSdk 37, **minSdk 29**.
- **UI:** Compose BOM 2026.09.00 with stable material3 1.4.0, used only as a fallback under our own theme.
- **Architecture:**
  - Navigation 3 1.1.7.
  - Hilt 2.60.1.
  - Room 3.0.3, DataStore 1.2.1, WorkManager 2.11.2.
- **Backend and auth:**
  - supabase-kt 3.8.0 (auth, postgrest, functions) with Ktor 3.5.2 on OkHttp.
  - credentials 1.6.0 and googleid 1.2.1 for Google sign-in.
- **Media:** Media3 1.11.1. Recording uses `AudioRecord` writing 16 kHz mono WAV, which gives sample-exact timestamps and survives crashes.
- **Security:** Tink 1.23 with the Android Keystore for the session token.
- **Tests:** JUnit4, Robolectric 4.17, Roborazzi 1.75 for screenshots, Turbine, and Compose UI test.
- **Backend runtime:** Deno 2 Edge Functions with zod, deployed with `supabase functions deploy --use-api`.

## Repo layout
```
app/                    Compose screens (one package per feature), Nav3, Hilt wiring, debug scenario panel
core/domain/            pure Kotlin: models, state reducers, evidence validator, transcript diff,
                        exercise templates, HistoryFilter, provider + BillingProvider interfaces
core/data/              Room 3 schema/DAOs/views, DataStore, repositories, orchestrators, RecoveryRunner,
                        deletion + tombstones, WorkManager, supabase-kt client, auth, fake providers
core/media/             WAV recorder + level flow, TTS (quiet-aware), Media3 player (segment clip), interruptions
core/designsystem/      tokens, fonts, indication, components, voice visuals (AGSL orb, tick ring)
core/testing/           fixtures, fake clock/ids, sample transcripts
supabase/migrations/    0001_core.sql, 0002_billing.sql
supabase/functions/     process-attempt, redeem-invite, delete-account, billing-verify, billing-rtdn, _shared/
tools/blender/          presence scene scripts (phase 2); .blend files stay out of git
.github/workflows/ci.yml
```
`applicationId` is `app.prepsuite.android` (debug builds add `.debug`). It can still change freely before any testers install it.

## Design system: "not vibecoded"
- **Avoid:** purple gradients, Inter, emoji, sparkles, glassmorphism, stock M3 purple, FABs, pill nav indicator, score dashboards, all-caps labels, gradient text, and cards everywhere.
- **Fonts** (all OFL and bundled, licence text shipped in the app):
  - **Mona Sans** for the UI.
  - **Newsreader** (serif) for interview questions only.
  - Tabular numerals for timers.
- **Colour (dark-first, with a light theme):**
  - Warm graphite, not blue-slate: bg #0E0F0F, surface #161817 / #1E201F, text #ECEAE5, text2 #A8ACA8.
  - One muted teal signal colour, "Tide" #74C7B8, used only for listening, selection, focus and links.
  - Primary buttons use the ink (text) colour as the fill.
  - Every contrast pair passes WCAG AA, and no state is shown by colour alone.
- **Layout:** 4dp grid, 20dp gutters, radii 6/12/20dp, 1dp hairlines. Tonal elevation, no shadows in dark.
- **Icons:** Phosphor Regular (MIT), imported as individual vectors.
- **Theme implementation:** `PrepTheme` provides the tokens through CompositionLocals and also fills every MaterialTheme slot, with dynamic colour off.
- **Press feedback:** a custom indication (ink overlay plus a focus ring) instead of the ripple.
- **Motion:** M3 Standard tokens. No bounce and no staggered lists outside the voice screen.
- **Copy:** plain and warm ("What worked", "One thing to try", "Retry this part"). No "AI-powered".
- **Screens:** one ink-coloured primary button per screen, pinned at the bottom (PRD §5 table).

## Voice screen: majestic, JARVIS done tastefully
- **Principle:** every element has a job, sits at its own depth, and moves for a reason.
- **Movement:** slow base motion (under 0.3 Hz), with a fast attack (≈40 ms) and slow release (≈280 ms) when reacting to audio.
- **Layers:**
  1. A near-black field (#07090A) with grain.
  2. Parallax dust.
  3. An **AGSL orb**: analytic sphere, two noise shells for depth, fresnel rim, a filmic curve and dithering.
  4. A hairline **tick ring**: 60 ticks, one lights per elapsed second.
  5. The question in Newsreader 300, revealed word by word in sync with speech.
- **Two lights:** the interviewer is a cool light and you are a warm amber light. This is the JARVIS cyan/amber idea, kept restrained.
- **States:**
  - **IDLE:** the orb breathes.
  - **SPEAKING:** text-to-speech loudness drives the rim and core.
  - **Handoff:** "Your turn — tap Record" (recording never starts on its own).
  - **LISTENING:** warmth rises and the mic level drives the orb.
  - **THINKING:** a comet arc and honest status text.
  - **REVIEW:** the orb collapses into the waveform scrubber and the render loop stops.
- **Other modes:** reduced motion gives a static orb whose brightness still follows audio. Quiet mode has no speech and a labelled indicator.
- **Performance:** the orb renders at half resolution. There are three quality tiers: AGSL, lighter AGSL, and a Canvas fallback, stepped down for power-save or thermal pressure. The render loop pauses when the screen isn't resumed.
- **Swappable:** everything sits behind `PresenceRenderer(state, level, warmth)`, so the Blender assistant can replace the orb without touching the screen.

## Complex logic built now
1. **Auth:**
   - Lazy `signInAnonymously` the first time the server is needed.
   - Email-code upgrade via `updateUser(email)` then `verifyEmailOtp(EMAIL_CHANGE)`.
   - Google via Credential Manager with a hashed nonce, then `linkIdentityWithIdToken`. If the identity already exists, sign in to it instead.
   - The session is stored with Tink encryption in `noBackupFilesDir` (the default store is plain SharedPreferences).
   - Sign-out and delete-account.
   - Honest note: upgrading does not move history to another phone, because history lives only on the phone.
2. **Local data (Room 3):**
   - Tables: question, session, session_question, answer_attempt, transcript_version, transcript_token, processing_request, feedback_item, quiet_exercise, retry_link, consent_record, tombstone, progress_event.
   - Audio files are immutable. Transcript edits create new versions.
3. **State machines:** pure reducers covering PRD §10.
   - Each change persists the state and its pending side effects in one transaction, then runs the effects.
   - A test covers the full state × event matrix.
   - `RecoveryRunner` runs at startup: `recording` becomes `interrupted` (the WAV is repaired or deleted), processing becomes `failed_recoverable`, and orphaned audio files are cleaned up.
   - The quiet-exercise state machine reaches `voice_completed` only through its retry link (A6).
4. **Evidence validation:**
   - The model returns token spans only, never times.
   - `validateSpan` checks the quote against the span; `resolveTiming` rejects bad timing and falls back to "Exact segment unavailable".
   - `diffTranscript` (an LCS diff) marks changed timings uncertain and makes old feedback stale (A8).
   - Guards reject scores and personality words, and flag facts not in the user's own words (A9 heuristic).
5. **History filtering:**
   - A `session_summary` database view (attempts, has-retry, pending work, modes).
   - Filters: role, question, mode, status, date range, has-retry, and search.
   - Results are paged.
6. **Deletion:**
   - Tombstones are written in the same transaction, in-flight requests are cancelled, then rows cascade and files are deleted after commit.
   - Remote cleanup is retried by WorkManager.
   - A late-response guard discards any result that arrives after deletion (A11).
7. **Supabase `0001_core`:**
   - Tables: profiles, consents, processing_requests (unique per user and idempotency key), usage counters, limits (with a kill switch), invites, tombstones.
   - Every table gets explicit GRANTs, row-level security with `(select auth.uid())`, and a private schema for security-definer functions.
   - `reserve_processing` / `finalize_processing` Postgres functions: atomic idempotency plus per-user and global caps, with locks taken in a fixed order.
   - pg_cron purges old data.
   - Edge Functions: `process-attempt` (fake provider, zod validation, quote checks, no content in logs), `redeem-invite`, `delete-account`.
8. **Checkout, `0002_billing`:**
   - Tables: `play_purchases` and an append-only `credit_ledger`, with a unique (reason, source_key).
   - `reserve_credit` spends the credits that expire soonest first, and reverses on failure.
   - `billing-verify` (Google Play Developer API with a service-account JWT) and `billing-rtdn` (Pub/Sub token check), both tested against stubbed Google responses.
   - Kotlin side: a `BillingProvider` interface, a debug-only `FakeBillingProvider`, and a paywall screen.
   - Saved recordings, deletion and privacy controls are never paywalled.
9. **Providers:**
   - **Real now:** TextToSpeech, the WAV recorder, the Media3 player.
   - **Fakes:** `Transcriber`, `FeedbackEngine` and `ExerciseGenerator`, which is deterministic and genuinely useful with no AI for the shorten and add-contribution templates.
   - A debug scenario switch: no timing, silence, network fail, timeout, invalid output, quota exceeded.
10. **Privacy:**
    - Backups: `allowBackup=false`, plus `dataExtractionRules` and `fullBackupContent` that exclude the database, audio and tokens.
    - Cleartext network traffic is off.
    - FLAG_SECURE on the record, transcript and feedback screens, with a debug toggle.
    - Release logs use a Timber tree that drops personal data; Supabase/Ktor logging is off in release.
    - Nothing is sent before consent.

## Execution (parallel agents, per AGENTS.md)
**M0: Foundations (I do this inline, because it's the shared contract):**
- Install the tools: `sdkmanager "platforms;android-37.0"`, `brew install supabase/tap/supabase deno`.
- Gradle wrapper, version catalog, the 6 modules, Hilt, the Nav3 shell (Practice · Quiet practice · History, plus Settings).
- The domain interfaces and models that every agent codes against.
- The `local.properties` → BuildConfig pipeline for the URL and publishable key.
- Manifest security (backup rules, network config) and `.gitignore` additions.
- `ci.yml`: gitleaks with a custom `sb_secret_` rule; Android lint, unit tests and assemble; Deno lint, check and test; migration deploy on manual trigger only.
- Push on a branch, open a PR, merge once CI is green.
- *Check:* the shell launches on the emulator.

**M1: Build wave, 8 agents in parallel.** Each works in its own worktree and owns a separate folder:
1. Domain logic and its unit tests (`core/domain`).
2. Room schema, DAOs, view, repositories, recovery, deletion (`core/data/db`).
3. Media: recorder, TTS, player, interruption handling (`core/media`).
4. Design system tokens, fonts, components, Roborazzi snapshots (`core/designsystem`).
5. Voice visuals: AGSL orb, ring, dust, quality tiers, demo screen (`core/designsystem/voice`).
6. Supabase `0001_core` plus the core functions and Deno tests (`supabase/`, core files).
7. Billing: `0002_billing`, the billing functions, and the Kotlin BillingProvider plus fake (`supabase/` billing files, `core/data/billing`).
8. Auth client: supabase-kt setup, Tink session store, anonymous/OTP/Google flows, auth screens (`core/data/auth`, `app/auth`).

I merge each branch as it finishes, fix anything that clashes, and CI stays green.

**M2: Screens and loops (me plus 3 agents):**
- All the screens in the PRD §5 table.
- Loop A: record → review → feedback → replay the exact part → retry → compare.
- Loop B: quiet exercise → save for voice practice → linked retry.
- History filters, settings and privacy, the debug scenario panel.
- *Check:* both loops complete on the emulator.

**M3: Backend deploy.** After you've done your steps below:
- `supabase db push --dry-run` then `db push`, `functions deploy --use-api`, `secrets set`.
- A two-user row-level security test script (bun + supabase-js, run against dev).
- **Don't run `supabase config push` as-is:** the current `config.toml` would overwrite the hosted auth settings.

**M4: Review wave, 5 agents in parallel:**
- Correctness code review.
- Security and privacy review (A10–A12, plus a canary phrase that must never appear in logs or network traffic).
- Design review of emulator screenshots against the "not vibecoded" checklist.
- Accessibility: TalkBack and 200% font.
- A test runner on the emulator.

Then I fix what they find and merge.

**M5: Blender assistant (gated).**
- Only runs if the usage check shows more than 50% remaining after M4.
- `brew install --cask blender` (5.2 LTS, about 346 MB) and `ffmpeg`.
- `tools/blender/build_presence.py` runs headless and renders with Cycles on the Metal GPU. The script must call `get_devices()` first, or Blender silently renders on the CPU.
- **The asset:**
  - A volumetric luminous core inside nested glass shells, with engraved rings and ticks.
  - Four seamless 4-second loops: idle, listen, speak, think.
  - Rendered on black, then encoded to H.264 (about 3 MB in total).
- **Art direction:** 3 agents each propose a direction, I review the rendered stills, and we iterate.
- **In the app:**
  - A `CinematicPresence` renderer plays two Media3 TextureViews and crossfades between them on each state change.
  - The AGSL field, ring and glow layer reacts to audio every frame.
  - It replaces the orb through `PresenceRenderer`.

## What you need to do (I can't: passwords, dashboards and accounts are yours)
1. **Before M3:** run `supabase login` in your terminal, then `supabase link --project-ref qtwhzseowgktmocsjwib`. The link step asks for the database password.
2. **Supabase dashboard → Auth:**
   - Turn on anonymous sign-ins and manual linking.
   - Set the email OTP template to `{{ .Token }}`.
   - Copy the **publishable key** (`sb_publishable_…`) to me. It isn't secret.
3. **Google Cloud (for Google sign-in):**
   - Set up the OAuth consent screen.
   - Create a Web client ID and an Android client ID. The Android ID needs the package name and debug SHA-1, which I'll print for you.
   - Paste the Web client ID into the Supabase Google provider.
4. **Before any tester uses email codes:** set up custom SMTP (a domain plus Resend or similar). The built-in sender only reaches your own team, at 2 emails per hour.
5. **Before real purchases:**
   - A Play Console account ($25).
   - Products created.
   - A service account.
   - A Pub/Sub topic for purchase notifications.
6. **Before the pilot:**
   - Create a separate prod Supabase project.
   - Choose quota numbers and a monthly spend cap.
   - Choose the voice and AI providers.

Steps 1–3 unblock M3. Everything before that runs without them.

## Verification
- **Unit tests:** `./gradlew :core:domain:test :core:data:testDebugUnitTest` covers the reducers, validator, diff, filters, recovery and deletion.
- **Emulator:** `./gradlew connectedDebugAndroidTest` (Room migrations, FK enforcement, Compose flows), plus `./gradlew roborazziVerify`.
- **Manual on the emulator:**
  - Install, then screenshot with `adb exec-out screencap` after each milestone.
  - Kill the app mid-recording (`adb shell am kill`) and confirm recovery.
  - Simulate a call (`adb emu gsm call`) and confirm the interruption is handled.
  - Airplane mode for A10.
  - Quiet mode, then kill and reopen, for A7.
- **Mic-driven orb:** turn on host microphone input in the emulator settings.
- **Backend:** `deno test` for the functions (quota races, idempotent replay, late output discarded, stubbed billing signature checks), plus the two-user RLS script against dev.
- **Secrets:** gitleaks in CI, and `grep` the built APK for `sb_secret_`.
- **Acceptance cases:**
  - Covered: A1, A2 logic, A4–A8, A10, A11 local part, A13 limits, A15.
  - **Not satisfiable until real providers exist:** A3 (timing accuracy), A9 (review of real model output), and parts of A12 and A14.

## Risks
- AGP 9.3.3 was chosen because of your Studio version. We can move to 9.4 after a Studio update.
- The emulator's M3 GPU is far faster than real phones, so the visual quality tiers still need calibrating on a real device.
- The Google identity-linking call needs a small spike to confirm. The fallback is browser OAuth with a `prepsuite://` deep link.
- Free Supabase projects pause after 7 days of inactivity.
