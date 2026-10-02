# PrepSuite — Interview Confidence

Product requirements document · 2 October 2026 · Version 2.0

## 1. Decision and purpose

PrepSuite helps first-time interviewees practise relevant questions, understand one concrete improvement, and hear the difference in their next attempt. Its recognizable robot characters make the experience welcoming and consistent; its practical value comes from the quality of the practice and feedback.

**Product promise: practise one answer, improve one thing, hear your progress.**

The builder's primary goal is a useful, finished project with authentic evidence of development and user benefit for a summer-camp application essay. Revenue is secondary. The project should demonstrate problem discovery, technical decisions, iteration and honest results, rather than maximize features or claim untested impact.

This PRD supersedes conflicting product scope in `INTERVIEW-APP-PRD.md`. The owner has now explicitly retained the robot visuals. The exploratory study-planner and app-blocking pivot is not the chosen direction. This document specifies future work; it does not claim that the complete experience is implemented.

## 2. Audience and problem

Initial audience: students and first-time candidates preparing for entry-level job interviews, especially people who have useful school, volunteering or project experience but struggle to explain it aloud. Start with English and one general first-job pack. Program or summer-camp interview packs can follow after the first pack is tested.

The user needs to answer four practical questions: What should I practise? What specifically needs improvement? How do I practise that improvement? Did my next attempt change?

Confidence is the intended user benefit, assessed through the person's reported preparedness and willingness to practise. Acoustic measurements describe speaking habits; they do not establish confidence, nervousness, personality or likelihood of getting a job.

## 3. Research and positioning

ChatGPT already supports natural spoken conversation. Conversation with an AI is therefore an insufficient differentiator by itself. [OpenAI voice documentation](https://help.openai.com/en/articles/20001274-chatgpt-voice).

Yoodli already offers interview practice and speaking reports including pacing and filler words. Voice analytics are an existing product category, not a novelty claim. [Yoodli interview preparation](https://yoodli.ai/use-cases/interview-preparation).

Duolingo's published method emphasizes structured, interactive activities and feedback. The relevant design inspiration is a coherent practice system with a recognizable identity. Its language-learning findings do not prove that PrepSuite improves interview confidence. [Duolingo Method research report](https://duolingo-papers.s3.amazonaws.com/reports/Duolingo_whitepaper_duolingo_method_2023.pdf).

**Positioning hypothesis:** a compact, approachable interview practice routine with reviewed questions, precise feedback, saved attempts and an easy comparison may help first-time candidates practise more consistently. The robot supports that routine. Test this hypothesis with actual users; do not claim market uniqueness or superiority over general assistants.

## 4. Core experience

1. Choose a robot and a target role. Start as a guest; optional background notes describe real experiences.
2. Choose one question for a quick drill or three questions for a short session.
3. Read or hear the question. Start and stop recording explicitly; typing is always available.
4. Replay the recording and review the transcript. Correct recognition errors before submitting.
5. Receive one strength, one priority improvement, supporting evidence and one useful delivery observation when reliable measurements exist.
6. Choose **Practise this**. Receive a short exercise addressing that one issue, then record a new attempt.
7. Play **Original** and **Retry** separately. See what changed in content or delivery, including an unchanged or uncertain result.
8. Finish with concise interview notes and one suggested next practice. Reopen saved attempts later.

Example: an answer says “we organized everything.” Feedback asks what the candidate personally did. A short drill prompts one truthful action and its result. The retry is compared with the original; the app points out whether the contribution is now explicit.

## 5. MVP scope and priorities

| Priority | Requirement | Completion condition |
| --- | --- | --- |
| P0 | Reliable question → recording → transcript → feedback | The user can finish without losing an answer; failures have a useful retry or typing option. |
| P0 | Reviewed question pack | 12 questions with skill, difficulty, follow-up intent and feedback criteria; no duplicate question in a session. |
| P0 | Immutable attempts and replay | Original and retry remain independently playable and survive an app restart. |
| P0 | Focused coaching | Every suggestion has an exact quote or an explicitly missing element, plus one action. |
| P0 | Honest voice observations | Feedback uses measured audio signals and states when measurement is unavailable or unreliable. |
| P0 | Coherent robot experience | The chosen character, colours and accessible controls remain consistent across the practice loop. |
| P1 | Small skill path | Four practice groups: introducing yourself, explaining an example, answering a follow-up, and clear delivery. |
| P1 | Quiet exercises | A short active text exercise connects to a later spoken retry; text completion is distinct from speaking improvement. |
| P1 | Useful history | Saved comparisons and suggested next drills are available without starting a new interview. |
| Later | Accounts and optional payment | Added only for a defined need after the local pilot works. |

The first demonstrable release is one role pack, three-question sessions, one focused retry per answer and working comparison. Additional languages, large question libraries and unrestricted chat are outside this first release.

## 6. Questions and learning design

The initial bank covers motivation, strengths with evidence, teamwork, solving a problem, learning from a setback and customer-facing situations. Questions must be realistic for someone without paid work experience. School, volunteering and personal projects are valid examples.

Each question stores an identifier, version, category, intended audience, difficulty, assessed skill, rubric and permitted follow-up. Generated variants must preserve the skill and difficulty. Review generated questions before adding them to the initial pack.

Allow one relevant follow-up per answer. It must refer to what the candidate actually said or ask for a genuinely missing detail. Do not invent personal facts, achievements, employers' criteria or numerical outcomes.

Use a small content rubric: relevance, specific evidence, personal contribution, understandable sequence, and result or learning where appropriate. STAR can guide behavioural examples; motivation questions do not need an artificial STAR structure.

Exercises should vary the action: identify an irrelevant sentence, replace a vague contribution, give a concise opening, add a truthful result, or answer a specific follow-up. Repeating a full mock interview is unnecessary when a short drill addresses the problem.

## 7. Voice analysis and feedback

The existing local analyzer computes speaking pace, pauses, transcript fillers, loudness patterns and pitch variation. Source-reviewed capability does not imply accuracy across all microphones, accents or environments.

| Signal | Useful feedback | Required limit |
| --- | --- | --- |
| Pace | Show measured rate and suggest a pause between ideas when appropriate. | Faster or slower is not automatically worse; never impose one universal ideal. |
| Pauses | Identify a long gap or demonstrate deliberate pauses. | Separate leading/trailing silence and recording problems from speaking pauses. |
| Fillers | Suggest replacing one repeated filler with a short pause. | Counts depend on transcription; natural uses of words such as “like” are not automatically errors. |
| Loudness | Highlight a fading ending and suggest a steady microphone position. | Microphone distance and background noise can affect the measurement. |
| Pitch variation | Suggest emphasis on an important phrase when the estimate is reliable. | Do not prescribe a voice pitch or infer emotions, identity or employability. |

Show one actionable delivery observation after an answer, with optional details. Deeper analysis should connect a reliable observation to a playable passage and a focused drill, rather than display a dashboard of unexplained numbers.

Use timestamped passages only when supported by recorded audio and reliable alignment. If alignment is unreliable, offer whole-answer replay or user-selected playback; never invent a precise error timestamp.

Typed answers receive content feedback only. A corrected transcript must not silently reuse invalid transcript-dependent measurements. Preserve the original recognized transcript and analysis; recompute supported values or clearly withhold affected observations.

The content model receives the transcript and measured signals, not an invented account of how the recording sounded. It must acknowledge insufficient evidence and preserve the candidate's facts. Users can correct the transcript or report unhelpful feedback.

## 8. Attempt storage and comparison

Each attempt is immutable and linked to its question and session. Store: local attempt identifier, parent/original attempt identifier, question version, mode, creation time, transcript versions, optional local audio path, optional measurements and analysis version, reliability flags, feedback and selected practice objective.

A retry creates a new attempt instead of replacing the original. Save an answer before requesting remote feedback. Reopening the app must retain saved work even if feedback or final notes failed.

Comparison shows two clearly labelled attempts, independent playback and the shared practice objective. Content and delivery observations remain separate. A shorter answer is not automatically an improvement; a valid result may be improved, unchanged or uncertain.

Keep recordings local by default with an explained retention choice and visible session/all-data deletion. Cloud audio upload is outside the MVP. Do not treat completing a typed exercise as demonstrated vocal progress.

## 9. Visual and character requirements

Retain the existing robot family and the owner's approved looks. Choose one consistent default mascot while allowing existing character selection. Do not redesign or regenerate protected model assets as a side effect of implementing practice logic.

Use recognizable asking, listening, thinking, speaking and encouraging states. Motion should explain activity and respond to voice; static thumbnails, hidden-screen animation suppression and reduced-motion support remain required.

The app should feel like a deliberate interview product: clear hierarchy, readable questions, restrained character scale, concise feedback cards and one obvious next action. The character should not obscure answers or controls. Subtle glass-like surfaces can support the existing visual direction when contrast and performance remain good.

Prefer encouragement tied to effort or an observed change. Show completed practice skills and saved attempts. Avoid punitive streaks, excessive rewards, leaderboards and fabricated confidence scores.

Required screens: brief onboarding/character choice, Practice home, session setup, question/recording, transcript review, feedback/drill, comparison, final notes/history, and privacy/settings. Existing navigation can remain where it supports this flow; a complete shell redesign is not required.

## 10. Reliability, privacy and accessibility

- Microphone permission is requested when recording is needed. Recording, cancellation and stop states are unmistakable. No real-interview listening or covert assistance.
- Disclose remote processing of transcripts and measurements before submission. Keep provider credentials server-side. Demo responses must be visibly labelled; an outage must not silently switch to fabricated AI feedback.
- Preserve saved answers across outages. Prevent duplicate submissions. Make speech preparation progress visible without blocking basic navigation.
- Spoken prompts and feedback also appear as text. Quiet mode stays quiet across the flow. Controls support screen readers, enlarged text and reduced motion.
- Validate layouts on small/large phones, landscape and with keyboards. User actions must remain reachable, not merely free of overflow messages.
- Preserve the rendering optimizations already made. Validate actual recording/playback and responsiveness on a physical Android phone before the pilot; emulator results alone are insufficient. iOS support needs its own validation.
- Keep the pilot local and bounded. Provide deletion without requiring a purchase. Any recordings retained for research require separate participant consent.

## 11. Accounts, pricing and operating cost

The pilot works without an account. Add a single sign-in method later only if cross-device recovery or an actual paid entitlement needs it. Audio does not automatically become cloud-synced when login is added.

The owner suggested US$0.99 as an optional price. Treat this as a proposed amount, not a committed subscription model, validated price or proof of sustainable costs. Decide the purchase type and paid benefit before implementing billing; follow the target store's current requirements when that phase begins.

Budget AI calls through short sessions, bounded follow-ups/retries, response caching where appropriate and explicit usage limits. Record cost per completed session during testing. Revenue is not a prerequisite for demonstrating useful project work.

## 12. Pilot and evidence for the essay

Recruit a proposed 5–8 volunteers from the intended audience. Each completes a three-question session and at least one retry. Ask them to rate preparedness before and after, explain whether feedback helped, and identify confusing moments.

Record attempted/completed sessions, successful saved comparisons, errors, reported usefulness and whether people voluntarily return for another practice. A simple review rubric can compare relevance, specific contribution and clarity; describe who reviewed the answers and what they knew about the attempts.

Keep a short evidence log: problem observed, feature tested, participant feedback, change made and outcome. Include unsuccessful sessions and feedback that challenged the design. Do not fabricate testimonials, users, revenue or improvements.

This small pilot can provide usability evidence and preliminary observations. It cannot establish that the app causes interview success or that self-reported preparedness is an objectively measured personality change.

## 13. Build sequence and acceptance gates

1. **Preserve the working foundation:** verify the real voice/question flow, network failure handling and current robot performance. Review the initial 12-question pack.
2. **Build the differentiating loop:** retain recordings, introduce immutable attempts, save measurements with reliability metadata, add focused retries and independent comparison playback.
3. **Improve the experience:** implement the four skill groups, short drills, coherent feedback hierarchy and character states. Coordinate visual work with Claude; avoid simultaneous edits to shared files.
4. **Validate:** test real audio and mixed phone layouts, then run the small pilot and make the highest-value fixes.
5. **Optional release features:** choose account and payment scope from actual needs after the pilot. Preserve guest access to the first meaningful practice.

MVP acceptance requires: one complete three-question session; evidence-linked feedback; a genuine original/retry comparison surviving restart; truthful voice availability labels; no answer loss during a recoverable error; usable large-text/keyboard layouts; and participant-controlled deletion.

The implementation handoff should distinguish existing source-reviewed foundations—robots, voice capture/transcription, delivery analysis, typed answers, feedback and local session patterns—from proposed additions: a curated curriculum, retained comparison recordings, immutable attempt history and a validated confidence-building routine. No runtime or pilot result is claimed merely because it appears in this PRD.
