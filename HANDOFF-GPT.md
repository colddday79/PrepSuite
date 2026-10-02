# PrepSuite — GPT handoff

**Purpose of this file:** if the context window fills up, read this file first in a fresh chat. It has everything needed to resume without re-deriving it.

**Owner:** colddday79@gmail.com
**Last updated:** 2026-10-01 (Asia/Seoul), by GPT. Maintain only this handoff; do not modify `HANDOFF-Claude.md`.

## Current checkpoint — read this first

This update is documentation only. The latest user request is to update GPT's handoff and leave Claude's handoff alone. No app edits, builds, deployments, commits or pushes were requested or performed in this update. The preceding home-screen message was a request to correct spelling, with an explicit “don't code anything”; its design requirements below are recorded for later work, not permission to resume implementation now.

### Verified from the checkout on 2026-10-01

- Active repository: `/Users/macintosh/Documents/PrepSuite`, branch `main`, HEAD `e8a0a4e` — “Calm the coach picker: one row of looks, a big preview, muted accent colours, and Tide instead of Pilot”.
- `origin`: `https://github.com/colddday79/PrepSuite.git`. `old-origin` retains `https://github.com/jungwooshim1212/PrepSuite.git`. Remote configuration does not prove current push authorization or that local work has been published.
- Both handoffs are at the repository root. Planning documents are now available at `docs/INTERVIEW-APP-PRD.md` and `docs/BUILD-PLAN.md`. The old iCloud path supplied as the chat working directory does not currently exist; use the Documents checkout explicitly.
- The app is Flutter at the root, with `lib/`, `android/`, `ios/`, `test/`, and `packages/prepsuite_speech/`. Earlier Kotlin code remains in `legacy/android-native/`.
- Current source includes onboarding, home, practice, interview, talk, history, profile and wrap-up screens. `lib/app/app.dart` restores sessions, profile and assistant preferences. Session persistence has a shared write queue and save-failure state.
- Current assistant names in `lib/app/assistant.dart` are Tide, Ember, Echo, Sprout and Orbit. These are observations of the current code, not GPT changes or a new instruction to edit their models.
- Before this update, the working tree already contained modifications to `HANDOFF-GPT.md`, `lib/design/assistant_avatar.dart` and `tools/blender/models/assistant.py`, plus untracked `tools/blender/models/export_assistant.py`. Preserve those changes. Their ownership and completion were not established here.

### Implementation carried from the earlier GPT pass

GPT worked on session restoration and serialized save/delete operations; preventing duplicate practice starts; retrying pending final notes; showing save failures and explicit sample labels; distinguishing typed/edited answers from measured voice delivery; accurate consent text for configurable AI providers; and rejecting incomplete feedback/notes responses. Speech lifecycle and backend validation work were delegated to two agents. Both agents hit usage limits before the combined work received final verification.

The backend agent reported a real three-answer Ollama flow with `mock:false` and 28 passing backend tests at that time. Treat these as historical agent reports, not proof of the current checkout. A complete five-answer live flow, current combined Flutter checks and physical microphone validation were not established by this GPT session. Later commits and Claude's work may have changed or completed these areas; inspect the current implementation before duplicating work.

### Current service setup and verification entry points

- `supabase/functions/coach/` contains the Deno coach service with Anthropic and Ollama providers. Current actions include `questions`, `feedback`, `wrapup` and `ask`. `tools/coach/README.md` documents the current contract and setup.
- `tools/coach/run-local.sh` attempts real AI by default. It can detect a model in the local Ollama app; `gemma4:31b-cloud` is the preferred name in the script. That model uses cloud inference and needs internet/sign-in. Without a configured provider, requests fail explicitly; `COACH_MOCK=1` enables sample mode. The root README's older “mock mode until a key is added” wording is stale.
- The app supports `COACH_URL`, explicit `COACH_FAKE=true`, `SPEECH_FAKE=true`/`SPEECH_DEMO=true`, `INTERVIEWER_VOICE=none`, and debug-only `SPEECH_TEST_WAVS`. Do not confuse recorded test fixtures with proof that a real phone microphone works.
- Speech model setup is documented in `packages/prepsuite_speech/README.md` and `tools/voice/fetch_models.sh`. Current model availability, running server health, provider sign-in, device connections and deployed Supabase status were not checked in this documentation update.
- When implementation is explicitly resumed, relevant checks are `flutter analyze`, `flutter test`, the package's speech tests, and `deno test --node-modules-dir=none supabase/functions/coach/`. For a configured real server, `deno run --allow-net tools/coach/smoke.ts http://127.0.0.1:8787` exercises five questions/answers, follow-up coaching and final notes using invented input. Check the existing process before starting another server.

### Continuation boundaries

- Leave Claude's handoff unchanged. The user previously confirmed Claude was editing this same repository; re-check files immediately before edits and preserve concurrent work.
- Do not modify the three protected 3D AI models or assets without a new explicit user request. Existing changes in model-related files are not permission to alter them.
- Prioritize the requested interview feature: approximately ten seconds to describe the job, editable transcription, relevant questions, short honest feedback on each answer, and useful final notes. Voice observations must come from measurements; do not infer emotion, personality or employability.
- The user says they have supplied an interviewer voice. Verify the current asset/integration before requesting or replacing a voice. Keep speech recognition, the speaking voice and the reasoning model conceptually separate.
- Preserve the home-screen design brief below. Consult [UI/UX Pro Max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) and the earlier [shadcn/ui reference](https://github.com/shadcn-ui/ui) when design work is authorized; adapt references to Flutter.
- The most recent discussion concerned variable Claude token usage. No token-related settings were changed. Do not carry forward the earlier unsupported inference that remaining cloud credits alone explain a spending-limit error; distinguish token counts, context occupancy, cost and credit pools, and inspect the actual meter when asked.

The sections below retain earlier product/planning context. Where they conflict, this checkpoint, the current code and the latest user instructions take precedence. They do not authorize new coding work.

### Current owner direction (2026-09-25)

The owner wants the existing interview flow made reliable before any visual redesign:

- The user records a short description of the job or interview they are preparing for.
- The app transcribes that recording on the device, lets the user correct the text, and sends the confirmed job to the coach.
- The coach generates relevant questions for that job, then reviews each spoken answer for content and measured delivery such as pace, pauses and filler words.
- Feedback must be short, direct, honest and evidence-based. Typed or edited answers must not receive claims about voice delivery.
- After the answers, the coach provides practical tips and last-minute interview notes. A failed final request must keep the completed answers available for retry.

The next design pass is the home screen only, after the flow works end to end. The owner wants the AI presence substantially larger (roughly 50–60% of the screen), with the glass panel positioned so it does not cover the presence, improved typography and a stronger overall hierarchy. The existing colour direction can remain a starting point. Review the UI/UX Pro Max reference supplied by the owner before making design decisions. Do not touch the three 3D AI models or their assets.

The owner explicitly asked for this handoff file to be updated without editing Claude's handoff. Claude may be working in the same checkout; preserve concurrent changes and do not rewrite files owned by that workstream.

---

## 1. What this project is

**PrepSuite** (working name; owner leans toward a mature, understated final name — see PRD §18) is an Android-first interview-practice app for people preparing for their first job. Core promise: *find one weak moment, work on it, and hear your next attempt beside the original.*

Two loops:
- **Loop A:** record an answer → transcript → one strength + one priority issue with an exact quoted moment → retry just that part → compare Original vs Retry side by side.
- **Loop B:** when speaking isn't convenient, do a short text exercise based on a real weakness → save it → later record a linked voice retry.

**The historical full PRD is `docs/INTERVIEW-APP-PRD.md`.** The user later narrowed the immediate scope to the voice interview feature described above. Useful constraints: no fabricated facts/scores, no employability judgements, local-first content, calm/plain UI with one main action per screen, and accessibility (TalkBack, no colour-only meaning). Original/retry comparison and quiet exercises below are historical product goals, not confirmed current functionality.

**The older build plan is `docs/BUILD-PLAN.md`.** Its Kotlin/Room/AGSL architecture is historical context, not the implementation authority for the current Flutter app. Consult relevant requirements without rebuilding the obsolete architecture.

---

## 2. Where things live

| What | Where |
|---|---|
| PRD | `/Users/macintosh/Documents/PrepSuite/docs/INTERVIEW-APP-PRD.md` |
| Build plan | `/Users/macintosh/Documents/PrepSuite/docs/BUILD-PLAN.md` (historical Kotlin plan) |
| This handoff | `/Users/macintosh/Documents/PrepSuite/HANDOFF-GPT.md` (this file) |
| Claude's handoff | `/Users/macintosh/Documents/PrepSuite/HANDOFF-Claude.md` — **do not edit this one**, it's the other assistant's copy |
| **Actual code repo** | `/Users/macintosh/Documents/PrepSuite` (separate from the iCloud docs folder — this is the real git checkout) |
| GitHub | `origin` is `colddday79/PrepSuite`; authentication, visibility and publishing status not reverified |
| Supabase | Historical dev project ref `qtwhzseowgktmocsjwib`; live plan, deployments and connectivity not reverified |

**Use `/Users/macintosh/Documents/PrepSuite`.** The old iCloud folder is absent as of this update. Do not recreate it or edit a similarly named folder by assumption.

The Flutter-root migration happened at `a356b1e`; the current observed HEAD is `e8a0a4e`. Re-check the branch and dirty files before any implementation work.

---

## 3. Historical planning decisions (not an active work queue)

These came from an `AskUserQuestion` the owner answered directly:

1. **Checkout/billing:** build the ledger + quota RPCs + `billing-verify`/`billing-rtdn` Edge Functions + a `BillingProvider` Kotlin interface with a debug fake, now. Real Google Play Billing wiring waits until the owner has a Play Console account.
2. **Auth:** lazy Supabase **anonymous sign-in** on first server need (keeps PRD's "no account required" promise intact — A1). Upgrade paths: **both email OTP and Google** (native ID token via Credential Manager + `linkIdentity`).
3. **Supabase environments:** `qtwhzseowgktmocsjwib` is **dev**. A separate **prod** project gets created before the pilot, not now.
4. **3D assistant approach:** **Blender Cycles pre-rendered loops (idle/listen/speak/think) + a live AGSL shader layer on top** reacting to voice in real time — not a real-time glTF/Filament model. Only build this if, after the core app + review passes, more than 50% of usage budget remains (owner's explicit gate).

Also decided earlier in-session (owner's original message, still binding where it does not conflict with the current direction):
- Must NOT look vibecoded. Keep the palette restrained and the hierarchy clear; avoid generic AI-dashboard styling.
- The owner now permits a controlled glass panel on the home screen, provided it does not cover the enlarged AI presence and remains readable.
- Voice screen must look "majestic," JARVIS-inspired but tasteful — full visual spec (palette, states, AGSL sketch) is in BUILD-PLAN.md §"Voice screen."
- The three 3D AI models and their assets are out of scope for the current redesign and must not be modified.

---

## 4. Historical environment snapshot (2026-09-23; do not use as current setup)

These installation/version statements are stale. Deno and Flutter were used in subsequent work. Check the current tools only when the next task needs them; do not install anything based on this snapshot alone.

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
- Built the Flutter project shell and the interview-practice flow: job intake, speech transcription confirmation, job-specific questions, answer feedback, wrap-up notes, local session persistence and retry states. Verify the live checkout and tests before treating any item as complete; concurrent work may still be in progress.

**Still to verify or do:**
- Run the Flutter analyzer and widget/integration tests against the current checkout.
- Verify a real coach request and the full retry/persistence path with the configured provider; sample mode must remain explicit and clearly labelled.
- Verify the on-device speech model files and microphone lifecycle on the emulator. Do not claim physical-device validation without a physical-device run.
- Only after the flow is reliable, redesign the home screen according to the current owner direction above.
- The old Supabase/Kotlin build-plan items are historical context until the owner explicitly returns the project to that architecture.

**Next implementation work, only when requested:** verify the current Flutter flow and reassess the existing home screen against the user's brief. Do not assume the September layout is still present. Keep the three protected 3D AI models unchanged.

---

## 6. Things a fresh session needs to know that aren't obvious from the files alone

- **AGP is pinned to 9.3.3, not the newest 9.4.1**, because the installed Android Studio can only sync 9.3.x projects. If the owner has since updated Studio, re-check before assuming this constraint still holds.
- **Ultracode / ECC context:** this session runs under the user's global `~/.claude/CLAUDE.md` and project `AGENTS.md`, which mandate: `/graphify` skill on trigger, and **launching multiple agents in parallel for any substantive product/UI/motion work** (8+ agents preferred) rather than single-agent passes — this shaped both the research phase and should shape the build-wave execution (BUILD-PLAN.md's M1 already specifies an 8-agent parallel build wave for exactly this reason).
- Historical Claude-specific attribution is not a requirement for GPT's commits or PRs. Do not attribute GPT work to Claude.
- **The owner's typing has frequent typos** ("emualter" → emulator, "sotred" → stored, "beldndering" → Blender) — read requests charitably and confirm ambiguous asks rather than guessing wrong.
- **Two assistants are collaborating on this project**: GPT (this file) and Claude (`HANDOFF-Claude.md`, a separate assistant's copy). **Only update HANDOFF-GPT.md, never HANDOFF-Claude.md** — that file belongs to the other assistant to maintain. If you need to know what Claude has done, you may read it, but never write to it.
- The PRD explicitly states numeric limits/schedule/pricing are *proposed defaults*, not commitments — don't treat "one to two weeks" or "3000 users" etc. as hard targets.

---

## 7. How to resume

1. Read the current checkpoint at the top and the latest user request. This handoff update does not resume coding.
2. Use the Documents checkout; inspect current Git status and applicable instructions. Preserve concurrent edits.
3. When code work is requested, inspect the current implementation and relevant tests before changing anything. Read only the relevant historical planning sections for that task.
4. Verify real provider, speech and persistence behavior as required; distinguish test reports from current runtime evidence.
5. For an authorized design pass, consult the supplied design references and the current screen. Preserve protected models.
6. Update only **this file**, never `HANDOFF-Claude.md`, when the user requests a handoff update.
