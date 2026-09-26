# PrepSuite — Handoff (Claude)

**Purpose of this file:** if the context window fills up, read this file first in a fresh chat. It has everything needed to resume without re-deriving it.

**Owner:** colddday79@gmail.com
**Last updated:** 2026-09-25 ~22:00 KST, by Claude (Opus 5.5). The app is Flutter at the repo root (Session 5). Session 6 is the latest app state (big presence on Home, real AI by default, the AI voice answering questions), and Session 7 (draft PR #1, merged on top of Session 6) adds the fonts, the coach's access token and security, and the every-phone layout test. Read Sessions 5 to 7 first; §2–§5 are historical.

---

## 1. What this project is

**PrepSuite** (working name; owner leans toward a mature, understated final name — see PRD §18) is an Android-first interview-practice app for people preparing for their first job. Core promise: *find one weak moment, work on it, and hear your next attempt beside the original.*

Two loops:
- **Loop A:** record an answer → transcript → one strength + one priority issue with an exact quoted moment → retry just that part → compare Original vs Retry side by side.
- **Loop B:** when speaking isn't convenient, do a short text exercise based on a real weakness → save it → later record a linked voice retry.

**Full requirements live in `INTERVIEW-APP-PRD.md`** in this same folder (iCloud `PrepSuite/`). Read it in full before making product decisions — this handoff summarizes but does not replace it. Key PRD constraints not to violate: no fabricated facts/scores, no employability judgements, local-first (no cloud sync of content), no account required to *start*, calm/plain UI with one main action per screen, accessibility (TalkBack, no colour-only meaning).

**The build plan lives in `BUILD-PLAN.md`** in this same iCloud folder (also copied to `/Users/macintosh/.claude/plans/sorry-please-plan-it-refactored-diffie.md`). It has the full architecture: module layout, Room schema, state machines, evidence-validation logic, provider interfaces, Supabase schema, design tokens, voice-screen visual spec, milestone sequence, and a "what only the owner can do" checklist. **Read BUILD-PLAN.md in full before resuming implementation** — it is the source of truth for how things should be built, not just what.

---

## 2. Where things live

| What | Where |
|---|---|
| PRD | `/Users/macintosh/Library/Mobile Documents/com~apple~CloudDocs/PrepSuite/INTERVIEW-APP-PRD.md` (iCloud, docs-only folder) |
| Build plan | same iCloud folder, `BUILD-PLAN.md` |
| This handoff | same iCloud folder, `HANDOFF.md` (this file) |
| GPT/Astra's handoff | same iCloud folder, `HANDOFF-GPT.md` — **do not edit this one**, it's the other assistant's copy |
| **Actual code repo** | `/Users/macintosh/Documents/PrepSuite` (separate from the iCloud docs folder — this is the real git checkout) |
| GitHub | private repo `jungwooshim1212/PrepSuite`, `gh` CLI is logged in as `jungwooshim1212` with repo+workflow scopes |
| Supabase | project ref `qtwhzseowgktmocsjwib`, displayed name "PrepSuite", Free plan, currently the **dev** project (owner decision: create a separate prod project before the pilot) |

**Do not confuse the two "PrepSuite" folders.** The iCloud one is planning docs only. The git repo is in `~/Documents/PrepSuite` and is NOT synced to iCloud (deliberately — Documents on this Mac isn't iCloud-synced, which keeps build output out of iCloud).

**Repo state:**
- `main` still has only the setup commit.
- The app lives on branch **`m0-skeleton`** (commit `b57aeef`), open as **PR #1**: https://github.com/jungwooshim1212/PrepSuite/pull/1. It is not merged; check CI and merge it first.
- It is one Gradle module, `:app`, package `app.prepsuite.android`. The debug build installs as `app.prepsuite.android.debug`.
- `supabase/config.toml` is untouched. There are still no migrations.

---

## 3. Decisions already made (do not re-litigate without owner sign-off)

These came from an `AskUserQuestion` the owner answered directly:

1. **Checkout/billing:** build the ledger + quota RPCs + `billing-verify`/`billing-rtdn` Edge Functions + a `BillingProvider` Kotlin interface with a debug fake, now. Real Google Play Billing wiring waits until the owner has a Play Console account.
2. **Auth:** lazy Supabase **anonymous sign-in** on first server need (keeps PRD's "no account required" promise intact — A1). Upgrade paths: **both email OTP and Google** (native ID token via Credential Manager + `linkIdentity`).
3. **Supabase environments:** `qtwhzseowgktmocsjwib` is **dev**. A separate **prod** project gets created before the pilot, not now.
4. **3D assistant approach:** **Blender Cycles pre-rendered loops (idle/listen/speak/think) + a live AGSL shader layer on top** reacting to voice in real time — not a real-time glTF/Filament model. Only build this if, after the core app + review passes, more than 50% of usage budget remains (owner's explicit gate).

Also decided earlier in-session (owner's original message, still binding):
- Must NOT look vibecoded. Research-backed design system exists in BUILD-PLAN.md (warm graphite dark palette, Mona Sans + Newsreader fonts, one muted teal accent, no purple/gradients/emoji/glassmorphism).
- Voice screen must look "majestic," JARVIS-inspired but tasteful — full visual spec (palette, states, AGSL sketch) is in BUILD-PLAN.md §"Voice screen."
- Owner will build the 3D assistant in Blender personally / with Claude's help — not urgent, gated behind the 50%-usage checkpoint above.

---

## 4. Environment facts (checked 2026-09-23, may drift — re-verify if stale)

- **Host:** Apple M3 Mac, 16 GB RAM, macOS 26.6.2 (Darwin 25.6.0), ~211 GB free on `/System/Volumes/Data`.
- **Android Studio:** 2026.1 ("Quail"), bundled JBR 21 at `/Applications/Android Studio.app/Contents/jbr/Contents/Home`. System `java` on PATH is **Java 8** — unusable for Gradle. Must set `JAVA_HOME` to the JBR path explicitly.
- **Android SDK:** `~/Library/Android/sdk`. Platforms installed: android-34/35/36/36.1. Build-tools 36.0.0. **API 37 platform NOT installed** — the plan calls for installing `platforms;android-37.0` via `sdkmanager`.
- **Emulator:** `Pixel_10_Pro_XL` AVD, Android 17 (API 37.1), Google Play image, arm64-v8a, **16 KB page size**, host GPU passthrough (GLES 3.0 via Metal translation on this Mac). Already booted and reachable via `adb` in earlier session (device id `emulator-5554`). Mic passthrough ("Virtual microphone uses host audio input") needs to be turned on per-session for realistic audio testing.
- **NOT installed on this Mac:** Supabase CLI, Docker, Deno, Blender, ffmpeg, gradle/kotlin standalone binaries. Homebrew, Node/npm/bun, and `gh` (authenticated) ARE installed.
- **No Docker means no local Supabase stack** (`supabase start`, `db reset`, `functions serve` all need it). Plan works around this: migrations pushed directly via `supabase db push` against the hosted dev project, functions deployed with `supabase functions deploy --use-api` (Docker-free path).
- Chosen toolchain versions (Gradle 9.7.1, AGP 9.3.3 — capped by this Studio version, not the newest 9.4.1 — Kotlin 2.4.20, Compose BOM 2026.09.00, supabase-kt 3.8.0, etc.) are fully enumerated in BUILD-PLAN.md's version table. Don't re-research from scratch; that table was verified against live sources by a research agent.

---

## 5. What has and hasn't happened yet

**Done:**
- Read the full PRD.
- Uninstalled Instagram and old SportSnap debug app from the emulator (unrelated cleanup, at owner's request, in an earlier chat — irrelevant to PrepSuite build but noted for completeness).
- Ran 8 parallel research agents (toolchain/versions, Supabase backend design, voice-screen visual/AGSL, design-system "not vibecoded", Blender→Android 3D pipeline, checkout/billing, security/privacy/CI, and a Plan-agent architecture pass) — findings are folded into BUILD-PLAN.md.
- Asked the owner 4 clarifying questions (see §3) and got answers.
- Wrote and delivered `BUILD-PLAN.md` (also exists as a Claude plan-mode file at `~/.claude/plans/sorry-please-plan-it-refactored-diffie.md`).
- Copied the plan into the iCloud PrepSuite folder as `BUILD-PLAN.md` per owner request.

**Done in session 2 (2026-09-23 evening). Owner said: skeleton only, no Blender yet, usage budget tight.**
- **How:** I built it myself in one pass, not with 8 agents, because the owner had about 23% of the 5-hour limit left. The AGENTS.md multi-agent rule was deliberately set aside for that reason.
- **Build:** `./gradlew testDebugUnitTest assembleDebug` passes, with 10 unit tests (`app/src/test/.../LogicTest.kt`).
- **Emulator:** the APK is installed on `emulator-5554`. I checked by screenshot: onboarding, home, voice session (speaking, your turn, record, review), History, and Quiet practice.
- **Files (all under `app/src/main/java/app/prepsuite/android/`):**
  - `App.kt`: the Application, with prefs, an in-memory `HistoryStore`, an `appScope` that outlives screens, and `audioDir` (in `noBackupFilesDir/audio`). Also `MainActivity`.
  - `designsystem/`:
    - `Theme.kt`: colour tokens (warm graphite plus voice tokens), the type scale (bundled Mona Sans and Newsreader variable fonts), Space/Radius/Motion tokens, and a custom press indication instead of ripple.
    - `Icons.kt`: a hand-drawn 1.5-stroke icon set.
    - `Components.kt`: PrimaryButton (ink fill), QuietButton, ListRow, RadioRow, FilterChip, SegmentedChoice, Tag, PrepToggle, TextInput, QuoteBlock, Notice, ConfirmDialog, TopBar.
  - `navigation/AppRoot.kt`: a hand-rolled back stack (a `Route` sealed interface) with animated transitions, the onboarding gate from DataStore, and 3 bottom tabs (Practice, Quiet practice, History).
  - `data/Model.kt`:
    - A 12-question bank (general plus customer service).
    - `HistoryFilter`: tab, role and text filters plus day grouping.
    - `SampleHistory`: six rows tagged "Sample".
    - `Exercises`: deterministic checks for the "Shorten it" and "Add your part" templates.
  - `data/Prefs.kt`: DataStore storing onboarded, quiet mode, role, session length and experience notes.
  - `feature/voice/`:
    - `VoiceVisuals.kt`: an AGSL orb shader (filaments, rim, core, bloom; API 33+ with a Canvas fallback), a TickRing (60 ticks that fill over the 2-minute cap, a drifting arc, a thinking comet), DustField, Waveform, and a reduce-motion check.
    - `Audio.kt`: `WavRecorder` (16 kHz mono WAV plus the level from the same buffer) and `QuestionSpeaker` (installed TTS; `speak` suspends until done).
    - `VoiceSessionScreen.kt`: the phase machine Idle → Speaking → YourTurn → Listening → Thinking → Review. It handles:
      - silence detection
      - the 2-minute cap
      - stopping on background
      - playback
      - adding the recording to history
      - a lazy mic permission request
  - Other screens: onboarding (3 steps), practice home and session setup, a feedback **preview** (clearly labelled "Example"), quiet practice, history, and settings (quiet toggle, storage used, delete all recordings, re-run setup).
- **Privacy defaults:** `allowBackup=false` plus extraction rules, cleartext traffic off, a TTS `<queries>` entry, and a proguard rule that strips debug logs.
- **CI:** `.github/workflows/ci.yml` runs gitleaks, then unit tests and the debug build.

**Deviations from BUILD-PLAN.md (deliberate, to save budget and risk):**
- **One module, not six.** Split into `core/*` modules later.
- **No Hilt, Nav3, Room or supabase-kt yet.** The hand-rolled navigation keeps the same "own the back stack" model, so moving to Nav3 is mechanical.
- **Toolchain pinned to versions already in the Gradle cache:** AGP 9.2.1, Gradle 9.4.1, Kotlin 2.4.0, **Compose BOM 2026.06.01**. BOM 2026.09.00 (Compose 1.12) failed the AAR check because it needs compileSdk above 36.
- **compileSdk and targetSdk are 36, not 37.** Platform 37 isn't installed.
- **Dark theme only.** The light palette is specified in BUILD-PLAN.md but not built.
- **No FLAG_SECURE yet.** It would black out adb screenshots; add it with a debug toggle.
- **History is in memory.** Real sessions are lost on restart until Room lands.
- **The speaking-state orb reacts to a synthetic envelope,** not real TTS audio.

**Done in session 3 (2026-09-23 night to 09-24): the Blender AI assistant is in the app.**
- **Blender:** 5.2.2 LTS is installed at `/Applications/Blender.app`. Everything is scripted and runs headless (`Blender -b --factory-startup --python-exit-code 1 --python <script> -- <args>`).
- **Design process:**
  - Three designer agents made variants A (Orrery), B (Data sphere) and C (Gyroscope core).
  - The owner chose a **blend**: A's gold latitude-band globe and crescents, C's arc-reactor core, and a light touch of B's data blocks and blue accents.
  - The final script is `tools/blender/variants/presence_final.py`. Outputs go to `tools/blender/out/final/` (gitignored), including `presence.blend`, which can be opened in the Blender GUI.
- **Blender 5.2 API quirks:**
  - The compositor is set with `scene.compositing_node_group` plus a `NodeGroupOutput`; Glare node settings are input sockets (`Type="Bloom"`).
  - For video output, set `image_settings.media_type = "VIDEO"` before `file_format = "FFMPEG"`.
  - Use the 'Standard' view transform. AgX bleached the amber toward white, and the owner does NOT want white.
- **The loop:** a 16 s seamless loop at 720px, 24 fps, 20 samples, exposure 0.35. It took about 5 minutes to render.
  - Stored in the app at `app/src/main/res/raw/presence_loop.mp4` (2.2 MB).
- **In the app:**
  - `feature/voice/PresenceVideo.kt` plays the loop: MediaPlayer on a TextureView, Screen blend so its black drops out, and a scale pulse driven by the voice level.
  - `VoiceSessionScreen` uses it in place of the AGSL orb. The AGSL orb code still exists as a fallback.
  - The voice-screen background is now near-black with an amber stage light behind the hologram and a vignette (the owner asked that the background make it noticeable).
  - The tick ring now appears only while recording.
  - Checked on the emulator by screenshot.
- **Someone else (probably GPT Astra) edited these without committing:** `Theme.kt` (new obsidian/sky-cyan palette, Newsreader removed), `Components.kt`, and several screens. I left them alone. Nothing from session 3 is committed yet; ask the owner before committing, because their files are mixed into the same working tree.
- **Higgsfield:** the account has 0 credits (free plan), so AI video generation isn't possible until the owner adds credits. The idea is to feed the Blender still in as both the start and end frame of a video model (e.g. `minimax_h3` or `flux_3_video`, which support start and end images) to get a more cinematic but still seamless loop.

**Next steps, in order:**
1. Check CI on PR #1, then merge it.
2. Owner steps from BUILD-PLAN.md: `supabase login` and `link`, turn on anonymous sign-in and manual linking, send the publishable key, and create the Google OAuth client IDs.
3. Room persistence, replacing `HistoryStore`, with the PRD §11 entities and the §10 state machine as a pure reducer.
4. Supabase `0001_core` migration and Edge Functions, then the auth client (anonymous first, then email OTP and Google).
5. Billing ledger plus a fake provider.
6. Real transcription and feedback providers when the owner has chosen them.
7. The Blender assistant, only when the owner says so and more than 50% of usage is left. It plugs in through the orb slot.

---

## 6. Things a fresh session needs to know that aren't obvious from the files alone

- **AGP is pinned to 9.3.3, not the newest 9.4.1**, because the installed Android Studio can only sync 9.3.x projects. If the owner has since updated Studio, re-check before assuming this constraint still holds.
- **Ultracode / ECC context:** this session runs under the user's global `~/.claude/CLAUDE.md` and project `AGENTS.md`, which mandate: `/graphify` skill on trigger, and **launching multiple agents in parallel for any substantive product/UI/motion work** (8+ agents preferred) rather than single-agent passes — this shaped both the research phase and should shape the build-wave execution (BUILD-PLAN.md's M1 already specifies an 8-agent parallel build wave for exactly this reason).
- **Attribution requirement for this session:** git commits end with `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`; PR descriptions end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- **The owner's typing has frequent typos** ("emualter" → emulator, "sotred" → stored, "beldndering" → Blender) — read requests charitably and confirm ambiguous asks rather than guessing wrong.
- **Two assistants are collaborating on this project**: Claude (this file) and "GPT Astra" (`HANDOFF-GPT.md`, a separate assistant's copy). **Only update HANDOFF.md, never HANDOFF-GPT.md** — that file belongs to the other assistant to maintain. If you need to know what GPT Astra has done, you may read `HANDOFF-GPT.md`, but never write to it.
- The PRD explicitly states numeric limits/schedule/pricing are *proposed defaults*, not commitments — don't treat "one to two weeks" or "3000 users" etc. as hard targets.
- **Building:** `export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"` first. Build from `~/Documents/PrepSuite`, never from the iCloud folder.
- **Driving the emulator:** use `adb shell input tap X Y` with device pixels (1344×2992). `uiautomator dump` works on static screens. The shell is **zsh**, so an unquoted `$var` doesn't word-split; use `read a b c d <<< "$var"`. Downscale screenshots with `sips -Z 1000` before viewing, to save tokens.
- **Emulator mic:** it gives silence unless "Virtual microphone uses host audio input" is on in the emulator's extended controls. So the app correctly reports "We couldn't hear anything". That isn't a bug.
- **The Mac sleeps on battery with the lid closed.** Long gaps in timings came from that, not from the app.
- **Voice orb design history:** the first shader version looked like a grey cloudy "moon". It was replaced with a ridged-noise filament version (a glassy sphere with luminous veins, a crisp rim, and a core), which the screenshots show looks far better. Keep that direction.

---

## 7. How to resume

1. Read `INTERVIEW-APP-PRD.md` in full.
2. Read `BUILD-PLAN.md` in full.
3. Read this file's §3 (decisions) and §5 (progress) to confirm nothing has changed since this was written.
4. Re-verify §4 (environment facts) — things like SDK platforms installed or Docker availability may have changed.
5. Resume at Milestone M0 unless the owner says otherwise.
6. Keep updating **this file** (not `HANDOFF-GPT.md`) as work progresses, so the next handoff is cheap.

---

## Session 4 (2026-09-24): enhanced assistant shipped; home screen brief

**Assistant (done, verified on emulator by screenshot):**
- The owner rejected three new concepts (`tools/blender/models/lexicon.py`, `attention.py`, `resonance.py`). Their verdict: "all look like shit".
- They chose to keep the gold globe, "much more enhanced".
- Winner: `tools/blender/models/gold_intelligence.py`. It adds:
  - comet pulses along the bands
  - HUD readouts (token rows, a histogram, a voice waveform)
  - a double measuring ring
  - a core about 1.5× larger
- Its loop (720px, 24 fps, 16 s, 4.4 MB) is now `app/src/main/res/raw/presence_loop.mp4`, played by `feature/voice/PresenceVideo.kt`.
- Headless Blender ignores the LINEAR keyframe preference. The models scripts force linear keys (`_make_linear`), so the loop no longer stalls.

**Billing context:**
- The Pro 5-hour limit was exhausted and extra usage was being billed.
- The owner has $100 in cloud session credits (expire Nov 5) and wants remaining work run in the cloud with multiple agents.
- The cloud has no Android emulator and no GPU Blender. Visual checks happen when a local session runs again.

**Home screen redesign brief (next task):**
- **Owner's words:** "slightly glassy but it DOES NOT LOOK LIKE AI".
- **The owner's list of 20 "vibecoded" tells to avoid:**
  1. purple-to-blue gradients
  2. gradient hero text
  3. emoji in headings
  4. Inter everywhere
  5. coloured-border cards
  6. glassmorphism cards everywhere
  7. low-contrast dark mode
  8. 3 icon boxes in a row
  9. badge above the headline
  10. Lucide icons everywhere
  11. untouched shadcn
  12. fade-in on scroll
  13. cursor-following beam
  14. buttons that fade on hover
  15. inconsistent spacing
  16. em dashes everywhere
  17. generic buzzword copy
  18. serif italic accents
  19. Space Grotesk + Instrument Serif
  20. grain over a gradient
- **Reference the owner pointed at:** UI UX Pro Max (uupm.cc, GitHub nextlevelbuilder/ui-ux-pro-max-skill), available as the `ui-ux-pro-max` skill.
- **Direction:**
  - Use glass only as a real material layer with something behind it. For example, a question panel over the gold hologram's glow with real blur (RenderEffect on API 31+, solid fallback), and a tab bar blurring the content under it.
  - Use a 1dp inner highlight, not coloured borders.
  - Put the gold hologram (a small live loop via `PresenceVideo`, about 200–240dp) at the top of Home as the brand centrepiece.
  - Warm near-black base, with contrast of at least 4.5:1.
  - Mona Sans only, and keep the custom hairline icons.
  - No stat tiles, no badge above the headline, no em dashes in copy. The UI copy currently has some, e.g. "Your turn — tap Record".
- **Watch out:** the GPT session's UI refresh (committed alongside this) already introduces several tells: `GlassCard` everywhere, `Tag` badges above headings, coloured icon tiles in onboarding, and a gradient primary button. Reconcile them deliberately.

---

## Session 5 (2026-09-25): rebuilt in Flutter, coach feature working, running on the owner's phone

**Big change: the app is Flutter now, not Kotlin.** The owner asked for this so one codebase covers Android and iPhone. The old Kotlin/Compose app is kept for reference at `legacy/android-native/` — do not delete it, but do not build new features there either.

**Repo moved to a new GitHub account.** It is now `github.com/colddday79/PrepSuite` (public), branch `main` (mirrors what was `m0-skeleton`). The old `jungwooshim1212/PrepSuite` repo is untouched and still has `origin`/`m0-skeleton` history up to commit `92be0d5`; this account's `gh`/git is now authenticated as `colddday79`. The old remote is kept as `old-origin` for reference.

**Local path moved back to `~/Documents/PrepSuite`.** The iCloud PrepSuite folder caused real damage this session: iCloud silently deleted the whole working copy once and created duplicate `android 2` / `build 2` folders another time, corrupting the Flutter build. **Do not put this repo, or any large/actively-built project, inside `~/Library/Mobile Documents/com~apple~CloudDocs/` again.** `~/Documents/PrepSuite` is a plain (non-iCloud) folder and is now the only working copy. If it ever needs restoring, it's a straight `git clone https://github.com/colddday79/PrepSuite.git` plus `tools/voice/fetch_models.sh` for the speech models (gitignored, ~143 MB).

**The owner's core feature is built and working end to end:**
1. Job intake: 10 s voice recording → on-device transcript (editable) → sent to the coach server.
2. Coach server generates 5 relevant interview questions for that job.
3. User answers each by voice (up to 2 min); on-device speech-to-text + delivery metrics (pace, pauses, fillers, loudness, pitch) computed locally; server returns short, honest, evidence-quoting feedback (headline, problem, quote, fix, "how it sounded", one strength). No scores, no fabricated facts.
4. Wrap-up screen: tips, last-minute notes, stories to use.
Verified via screenshots and a real device run — see `e2e_1..5_*.png` and `port_*.png` in the session's scratchpad (not committed; regenerate if needed).

**New pieces:**
- **Flutter app** at the repo root (`pubspec.yaml`, `lib/`, `test/`, `android/`, `ios/`). Entry `lib/main.dart`; coach flow in `lib/coach/**` and `lib/features/{consent,intake,interview,wrapup}/**`; ported screens (History, Quiet practice, Settings, Profile, onboarding) in `lib/features/{history,quiet,settings,profile,onboarding}/**` plus `lib/data/**` for local persistence. Design system ported to `lib/design/{tokens,components,icons,frosted_panel,hologram}.dart`, following the same "warm near-black, gold accent, one real glass panel, no vibecoded tells" rules as before.
- **`packages/prepsuite_speech/`**: a Flutter package, offline on-device speech-to-text (sherpa_onnx + a Kroko streaming ASR model, CC-BY-SA — needs a licence decision before release) and the owner's "Norman" Piper voice as the interviewer (`en_US-norman-medium`, MIT/public domain, verified against the owner's files in `~/Downloads`). `DeliveryAnalyzer` computes wpm, pauses, fillers, loudness, pitch/monotone from the raw PCM, pure Dart, unit-tested with synthetic signals. Models are NOT committed (~143 MB); `tools/voice/fetch_models.sh` rebuilds them after a fresh clone (downloads ASR + espeak-ng-data from k2-fsa/sherpa-onnx releases, converts Norman from `~/Downloads/en_US-norman-medium.onnx[.json]`). Without models present, the app falls back to typed input rather than failing.
- **`supabase/functions/coach/`**: the Claude-backed AI server (Deno + `@anthropic-ai/sdk`, model `claude-opus-5`, adaptive thinking, per-route effort, server-side refusal fallbacks). Single `POST /coach` endpoint with three actions (`questions`/`feedback`/`wrapup`) and `GET /health`. Runs locally now via `tools/coach/run-local.sh` on port 8787 (mock mode — **no Anthropic key is configured on this Mac yet**; the owner must add one per `tools/coach/README.md`, not me). Deploys later to Supabase project `qtwhzseowgktmocsjwib` with `--no-verify-jwt` (needs an auth layer before any real release, since that makes the endpoint public).
- **CI** (`.github/workflows/ci.yml`) now runs `flutter analyze` + `flutter test` instead of Gradle.

**Running it:**
```
cd ~/Documents/PrepSuite
tools/coach/run-local.sh &          # AI server, defaults to mock mode without a key
flutter run                         # emulator, or -d <device-id> for a real phone
flutter run --dart-define=COACH_URL=http://<mac-lan-ip>:8787/coach   # phone on same Wi-Fi
```
The owner's Galaxy S26 (SM-S942N, serial `R3KL708EVEH`) has the debug APK installed and working over the same-Wi-Fi coach URL as of this session. Mac's LAN IP was `192.168.45.212` — re-check with `ipconfig getifaddr en0` since it can change.

**Parallel-editing hazard this session:** at one point 2–3 agents (possibly including another assistant, "GPT Astra") were editing `packages/prepsuite_speech` and `supabase/functions/coach` simultaneously in the same working tree without git worktrees, causing an API-contract change (`SpeechCaptureAdapter`) mid-flight. It was resolved by the agents coordinating directly, but future multi-agent work on this repo should prefer isolated worktrees per agent (the `isolation: "worktree"` option) to avoid this, or explicitly partition files up front the way the prompts in this session did.

**Not done / next steps:**
- Add a real Anthropic API key so feedback is real, not sample output (owner's action, see `tools/coach/README.md`).
- Decide on the Kroko ASR model's CC-BY-SA licence (attribution needed) or switch to the Apache-2.0 `librispeech` alternative (`ASR=librispeech tools/voice/fetch_models.sh`), which is less accurate.
- espeak-ng (used to phonemise text for the Piper voice) is GPL-3.0 — needs a legal check before shipping.
- iOS was never built or tested this session (no Xcode on this Mac). sherpa_onnx claims iOS 13+ support but it's unverified here.
- Auth/abuse-prevention on the coach Edge Function before any public deploy.
- The repo is currently **public** on GitHub; the owner may want it private.

---

## Session 6 (2026-09-25 evening): big presence, real AI by default, the AI talks back

**Owner's asks (while away, "do not ask questions"):**
1. Make the AI presence about 50–60% of Home, with the "Tell me the job" panel moved below it.
2. Use the Norman voice so the AI actually talks back and answers what the user asks.
3. Make Start practice → 10 s job recording → AI questions actually work.
4. If usage allows: the profile and a better, non-vibecoded design (UI UX Pro Max as reference).

**Root cause of "the AI doesn't work":** the coach server on port 8787 was running in sample mode (`mock: true`), so questions were generic. Now:
- `tools/coach/run-local.sh` picks real AI by default. It uses the Ollama app's `gemma4:31b-cloud`; the owner is signed in, and a request takes about 1–2 s. `COACH_MOCK=1` is the only way to get sample answers.
- The server was restarted this way and verified end to end on the emulator:
  1. The Norman-voiced WAV "I am applying for a junior data analyst job at a hospital…" goes through the real on-device ASR.
  2. The AI writes five relevant questions.
  3. A spoken answer gets real feedback that Norman reads aloud.
  4. A spoken "How long should my answer be?" gets a contextual answer that Norman reads aloud.

**What changed:**
- **Presence video** re-rendered at 1440×1440 from the unchanged `tools/blender/models/gold_intelligence.py`:
  - render settings: `--res 1440 --samples 20 --fps 24 --seconds 16`, rendered as PNG frames and then encoded with ffmpeg (libx264 CRF 20, High@4.1, 5.2 MB);
  - poster frame at `assets/images/presence_poster.jpg`, shown until the video is ready and under reduced motion.
  - `tools/blender/out/` had been lost with the iCloud copy. Renders now live in the session scratchpad.
- **Home** (`lib/features/home/home_screen.dart`, `homePresenceSize`):
  - The presence box is min(width × 1.12, usable height × 0.55), about 50% of the screen. The globe fills the width, and only the outer ring and black corners run off the edges (`OverflowBox` in `hologram.dart`).
  - The frosted panel sits below it.
  - The headline uses `PrepType.display` 30/36.
  - Top-bar profile icon, a "Profile and history" row, and an interview countdown line from the profile.
- **Intake and interview:** the presence grows while Norman asks and listens (intake about 38% of the height, questions about 28%), and `CoachScaffold` animates size changes. The intake hint now asks for the role, where, and a known requirement. A target role from the profile pre-fills typing.
- **Voice** (`lib/features/interview/read_aloud.dart`, `ask_coach_panel.dart`):
  - Norman reads a spoken version of the feedback (headline plus fix, 45 words at most).
  - An inline "Ask the coach" panel takes a 15 s voice question or a typed one; the server's new `ask` action answers in 2–4 spoken sentences and Norman reads it.
  - The wrap-up has "Hear your notes", on request only.
  - Auto-play is skipped in typing sessions and when TalkBack is on.
- **Norman bug fixed:** a fixed audioplayers `playerId` made `speak()` hang forever after a hot restart, so the UI sat on "speaking". Playback that never starts now times out after 8 s.
- **New shared pieces:**
  - `CoachApi.ask` / `CoachReply`;
  - `lib/app/profile.dart` (`Profile`, `ProfileStore` in `AppServices.profile`, persisted under `profile.v1`);
  - icons `calendar`, `chat`, `stop`, `edit`.
- **`tools/run-phone.sh`:** starts the coach if needed and runs `flutter run` with `COACH_URL=http://<LAN IP>:8787/coach`. Use this for the Galaxy S26 (same Wi-Fi).
- **Profile** (`lib/features/profile/`, from the top-bar user icon or the "Profile and history" row):
  - name, target job, interview date and experience, saved as you type, optional and on the phone only;
  - practice history from `SessionStore.history` (newest first, capped at 30, key `interview.history.v1`, one row per practice through `startedAt`);
  - "Delete everything on this phone". `SessionStore.clearAll()` removes the practice plus history; Settings' delete now uses it too.
  - Reviewed notes go back one step on Done.
- **Design system** (`lib/design/components.dart`, `tokens.dart`, `prepTheme()` in `lib/app/app.dart`):
  - PrimaryButton is a solid warm-white slab with press darken and a 0.98 scale (the gradient is gone);
  - public `FocusRing` for keyboard and switch focus;
  - every Material text role mapped to Mona Sans (otherwise the variable font's thin 200 default leaks through);
  - themed date picker, dialogs, snackbars and sheets;
  - new tokens `PrepType.titleL/button/caption`, `PrepColors.focus/scrim`, `Motion.pressScale`;
  - contrast asserted in `test/design_test.dart`.
- **Accessibility fixes:** IconAction and RecordButton now expose their tap to TalkBack (before this, screen readers could not activate them).
- **State at the end:** 118 Flutter tests and 32 Deno tests pass, and `flutter analyze` is clean. Everything is pushed to `colddday79/PrepSuite` main. The coach server was left running on 8787 in real-AI (Ollama) mode.

**Next steps:**
- Run on the owner's Galaxy S26 with `tools/run-phone.sh -d R3KL708EVEH`, on the same Wi-Fi as the Mac.
- The Ollama cloud model is a stopgap for development. Before release, decide the provider (Anthropic key vs Ollama) and add auth to the coach.
- Licence decisions are still open: Kroko ASR (CC-BY-SA) and espeak-ng (GPL-3.0).
- The fix text can contain AI placeholders in square brackets, like "[wait times or bed occupancy]". Consider asking the prompt for plain words instead.
- **Tests:** the flow test's stale "Last-minute notes" finder was fixed (Home shows "Finish your interview notes" in that state). New tests are `home_screen_test.dart` and `ask_coach_test.dart`, plus ask cases in `coach_api_test.dart` and `coach_test.ts`.

**How the work was run:**
- Six agents, each in its own git worktree under `.claude/worktrees/` (gitignored). All six hit the session usage limit within about 15 minutes, having written little.
- After the reset, only the two agents with progress were resumed (coach server, voice). Home, intake and wrap-up were done directly, then the profile and design-system agents were resumed.
- Lesson: on this plan, six parallel Opus agents exhaust the 5-hour limit fast. Run two or three at a time, give each a narrow brief, and commit after each merge.

**Emulator testing without a microphone:**
- Test WAVs are synthesised with Norman via `tools/voice/.venv/bin/python` and `sherpa_onnx.OfflineTts` (see the session scratchpad `synth.py`).
- Push them to `/data/local/tmp/prepsuite/` (chmod 755 on the dir, 644 on the files).
- Run with `--dart-define=SPEECH_TEST_WAVS=/data/local/tmp/prepsuite/job.wav,...`; each recording consumes the next file.
- `flutter run --pid-file F` then `kill -USR1 $(cat F)` hot-reloads and `-USR2` hot-restarts.

---

## Session 7 (2026-09-25, cloud session, merged on top of Session 6): fonts, security, every phone

Branch `claude/wonderful-wright-ui4vwi`, draft PR https://github.com/colddday79/PrepSuite/pull/1. This ran
in a Claude Code cloud container: no emulator, no phone, no Mac apps. Flutter 3.47.5 and Deno 2.9 were
installed there for checks. It started before Session 6 on the same asks, then merged Session 6's `main`.

**Merge decisions:** Session 6's Home (presence about half the screen, frosted panel below it, Start
practice → intake), the intake screen, the 1440 px presence video and poster, the profile, ask the coach
and read-aloud are kept as they are. This session's own Home rework (the job recorded on Home itself,
`MicButton`, `HologramHero`, a 1080 px render) was dropped for them.

**What this session adds:**
- **Fonts.** Bodoni Moda (headlines, questions, the wordmark) and Jost (all other text): the "Luxury
  Minimalist" pairing from the UI UX Pro Max typography data (github.com/nextlevelbuilder/ui-ux-pro-max-skill),
  which the owner asked for. Mona Sans is removed. `PrepFonts` in `tokens.dart`, and `prepTheme()` maps
  every Material text role to them. Bodoni `opsz` = 0.55 × size, capped at 18 (hairlines vanished at the
  full display size on a phone).
- **Coach.** Claude calls send the per-route effort (it was defined but never sent), adaptive thinking,
  `max_tokens` = route cap + 12,000 (`THINKING_ROOM`) and server-side refusal fallback
  (`fallbacks: "default"`, beta `server-side-fallback-2026-07-01`). Questions follow the kind of
  interview named ("barista, group interview").
- **Security** (`SECURITY.md` has the full list and the owner's checklist): the coach answers only
  requests with its access token (`x-coach-token`), which `tools/coach/run-local.sh` creates in
  `supabase/functions/.env` and `tools/run-phone.sh` passes to the app. It also has rate limits, JSON-only
  requests and security headers. Android backup and device transfer are off and release builds are
  https-only. CI actions are pinned, gitleaks and Dependabot run, and a `coach` CI job was added.
- **Every phone.** `test/layout_matrix_test.dart` walks Home, settings, the profile (date picker, delete
  dialog), a whole practice (asking the coach, the end-practice dialog), the wrap-up read aloud, the history
  and typing, on 12 sizes at text ×1 and ×2. It fails on any layout error and on any text cut off by a
  box too small for it. Fixes it drove:
  - `HeadingScale` on the Home wordmark and headline (headings grow at most 30%);
  - scrollable alert dialogs;
  - the date typed instead of the calendar when the calendar can't fit (text above 1.3×, or under 560 dp of height);
  - a text-scaled slot for the hint under the interview's record button.
- **Presence.** The wrap-up's glass panel no longer overlaps its presence. The video pauses in the
  background and when the phone removes animations. The poster stays under the video, so there is no dark flash.
- **Tests:** 148 Flutter tests pass, and `flutter analyze` is clean. There are 8 more screenshot tests, which run
  with `--dart-define=SCREENSHOTS=true` and write `build/screenshots/`. 42 Deno tests pass.

**Not done / next:**
- Nothing here was run on a device. The Android app can't be built from the cloud (Google's SDK
  downloads are blocked).
- In a very short window (split screen), the intake's record button needs a scroll, because the
  presence keeps at least 200 dp there.
- The owner-only settings in `SECURITY.md`'s checklist.
