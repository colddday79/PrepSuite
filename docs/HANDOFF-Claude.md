# PrepSuite — Handoff (Claude)

**Purpose of this file:** if the context window fills up, read this file first in a fresh chat. It has everything needed to resume without re-deriving it.

**Owner:** colddday79@gmail.com
**Last updated:** 2026-09-23 ~20:40 KST, by Claude (Opus 5.5). The app skeleton is built, installed on the emulator, and open as PR #1 (not merged yet). See §5.

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
