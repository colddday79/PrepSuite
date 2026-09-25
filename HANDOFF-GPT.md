# PrepSuite — Handoff (GPT Astra)

**Purpose of this file:** if the context window fills up, read this file first in a fresh chat. It has everything needed to resume without re-deriving it.

**Owner:** colddday79@gmail.com
**Last updated:** 2026-09-23, seeded by Claude (Sonnet 5) at end of planning phase — no application code written yet. **GPT Astra: update this file yourself from here on, not Claude's `HANDOFF.md`.**

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
| This handoff | same iCloud folder, `HANDOFF-GPT.md` (this file) |
| Claude's handoff | same iCloud folder, `HANDOFF.md` — **do not edit this one**, it's the other assistant's copy |
| **Actual code repo** | `/Users/macintosh/Documents/PrepSuite` (separate from the iCloud docs folder — this is the real git checkout) |
| GitHub | private repo `jungwooshim1212/PrepSuite`, `gh` CLI is logged in as `jungwooshim1212` with repo+workflow scopes |
| Supabase | project ref `qtwhzseowgktmocsjwib`, displayed name "PrepSuite", Free plan, currently the **dev** project (owner decision: create a separate prod project before the pilot) |

**Do not confuse the two "PrepSuite" folders.** The iCloud one is planning docs only. The git repo is in `~/Documents/PrepSuite` and is NOT synced to iCloud (deliberately — Documents on this Mac isn't iCloud-synced, which keeps build output out of iCloud).

As of last check, the repo has exactly one commit ("Initialize PrepSuite service setup") containing only `README.md`, `.gitignore`, and `supabase/.gitignore` + `supabase/config.toml` (CLI-generated, unmodified). **No Gradle project, no app module, no migrations exist yet.**

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

**NOT done — this is the actual next work:**
- No Gradle project/app module created yet.
- No `local.properties`/SDK install for API 37.
- No Supabase CLI installed, no `supabase login`/`link` run.
- No migrations written or pushed.
- No Edge Functions written.
- No Android code of any kind written.
- No GitHub Actions CI file exists yet.

**Immediate next step per the plan:** Milestone M0 ("Foundations") — install tooling, scaffold the 6-module Gradle project (`app`, `core/domain`, `core/data`, `core/media`, `core/designsystem`, `core/testing`), wire Hilt + Nav3 shell, set up CI, push an initial PR. This was queued but not started as of this handoff (owner interrupted to ask for this handoff file instead of proceeding).

---

## 6. Things a fresh session needs to know that aren't obvious from the files alone

- **AGP is pinned to 9.3.3, not the newest 9.4.1**, because the installed Android Studio can only sync 9.3.x projects. If the owner has since updated Studio, re-check before assuming this constraint still holds.
- **Ultracode / ECC context:** this session runs under the user's global `~/.claude/CLAUDE.md` and project `AGENTS.md`, which mandate: `/graphify` skill on trigger, and **launching multiple agents in parallel for any substantive product/UI/motion work** (8+ agents preferred) rather than single-agent passes — this shaped both the research phase and should shape the build-wave execution (BUILD-PLAN.md's M1 already specifies an 8-agent parallel build wave for exactly this reason).
- **Attribution requirement for this session:** git commits end with `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`; PR descriptions end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- **The owner's typing has frequent typos** ("emualter" → emulator, "sotred" → stored, "beldndering" → Blender) — read requests charitably and confirm ambiguous asks rather than guessing wrong.
- **Two assistants are collaborating on this project**: GPT Astra (this file) and Claude (`HANDOFF.md`, a separate assistant's copy). **Only update HANDOFF-GPT.md, never HANDOFF.md** — that file belongs to the other assistant to maintain. If you need to know what Claude has done, you may read `HANDOFF.md`, but never write to it.
- The PRD explicitly states numeric limits/schedule/pricing are *proposed defaults*, not commitments — don't treat "one to two weeks" or "3000 users" etc. as hard targets.

---

## 7. How to resume

1. Read `INTERVIEW-APP-PRD.md` in full.
2. Read `BUILD-PLAN.md` in full.
3. Read this file's §3 (decisions) and §5 (progress) to confirm nothing has changed since this was written.
4. Re-verify §4 (environment facts) — things like SDK platforms installed or Docker availability may have changed.
5. Resume at Milestone M0 unless the owner says otherwise.
6. Keep updating **this file** (not `HANDOFF.md`) as work progresses, so the next handoff is cheap.
