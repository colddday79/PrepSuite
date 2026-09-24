# Interview Practice App — Product Requirements Document

Version 1.0 · 23 September 2026 · Planning only; no implementation authorised by this document

## 1. Product decision and document status

Build an Android-first interview practice app for people preparing for their first job. The app asks structured, relevant interview questions aloud, records answers, gives concise spoken and written feedback, and helps users practise the specific part that needs work. When speaking is inconvenient, users complete short active exercises based on their own previous answers, then return to a connected voice retry later.

The central promise is: **Find one weak moment, work on it, and hear your next attempt beside the original.**

This is the current brief for the new interview product. It replaces the newer Sportsnap review document. The older `SPORTSNAP-PRD.md` and its sections are historical material for an abandoned product; their requirements do not apply here. Sports competition, deadline planning, application blocking, motion recognition, 3D, and social networks are outside this product.

The audience, two learning loops, Android direction, low budget, and planning-only handoff are owner decisions. Numerical limits, schedule, initial roles, pilot targets, architecture, and pricing below are proposed planning defaults unless explicitly stated otherwise. Claude should use this document to develop an implementation plan, identify unresolved dependencies, and challenge feasibility; it is not an instruction to start building.

## 2. Problem, audience, and positioning

A first-time applicant may have useful experiences from school, volunteering, clubs, caring responsibilities, or personal projects but struggle to explain their contribution. Generic advice such as “be more specific” does not identify what to change. Repeating a whole mock interview is unnecessary when one sentence or missing result is the main issue. A person travelling or sitting around other people may also want to practise without speaking.

Primary audience: people preparing for first-job or entry-level interviews, including students with little paid employment history. Initial recruitment should focus on a small reachable group with an actual upcoming application, rather than all job seekers. The precise age range and first launch region remain a pre-beta decision because provider eligibility and data handling must fit the real participants.

Proposed first question packs: general first-job questions and one entry-level customer-facing role, selected after discovery. Start with English. Support users with varied accents without treating accent difference as a weakness. Specialist technical interviews, executive coaching, and comprehensive multilingual assessment are later opportunities.

The advantage being tested is a structured practice workflow: persistent evidence, precise replay, a focused retry, and quiet practice that reconnects to speaking. It is not a claim that this app has a smarter AI than a chatbot, is unique in the market, or improves hiring outcomes. Competitor uniqueness has not been validated.

## 3. Goals and boundaries

Users should be able to answer a relevant question, understand one actionable improvement linked to their own words, practise it without restarting everything, and review the attempts later. Quiet practice must require a useful action rather than passive reading or an open-ended chat thread.

The builder's near-term objective is a small useful prototype within approximately one to two weeks after implementation begins, followed by a real-user pilot. Evidence for an extracurricular essay should be truthful: observed use, iterations, feedback, and any real revenue. A previous aspiration of 3,000 users is not a validated milestone or forecast.

No real-time assistance during actual interviews, hidden overlays, meeting listening, employer integrations, fabricated achievements, personality judgements, employability rankings, or validated-sounding confidence scores. No camera requirement. No promise of detailed tone or prosody accuracy in the prototype. No social feed, leaderboards, resume ingestion, subscription infrastructure, or interruptible realtime conversation needed for the first demo.

## 4. End-to-end example

1. Alex chooses “First customer-service job” and a three-question practice session. An optional experience prompt lets Alex note a real school event they helped organise. No CV or account is required for the local prototype.
2. The app displays and speaks: “Tell me about a time you helped solve a problem.” Alex can replay the question, read it, or switch to quiet practice.
3. Alex explicitly starts recording, answers, and stops. The app saves the recording locally before processing. It explains any remote processing before submission and obtains the required consent.
4. Alex reviews the transcript and corrects a misheard name. The app returns one strength and one priority improvement. For example: “At 00:24–00:34 you say ‘we sorted everything out’. What did you personally do?” That timestamp is shown only if supported by the saved audio alignment.
5. Alex taps the feedback to hear the exact section with a little surrounding context, then selects “Retry this part.” The original remains saved. The prompt asks Alex to describe their own action; it does not invent one.
6. Alex records a short replacement. Two labelled cards show Original and Retry, with independent playback and corresponding text. Feedback explains the observed change, such as “Your retry now states your own action.” It can also say the issue remains or the result is uncertain.
7. The next day, in a quiet place where speaking is inappropriate, Alex opens a suggested exercise based on that same weakness: replace a vague sentence with one specific action they actually took. Alex writes a sentence and receives a short explanation.
8. The exercise saves a “Try this aloud” item linked to the original question and weakness. Later, Alex records it and compares it with the old segment. History shows the original, exercise, and retry together; completing the text exercise alone is not recorded as demonstrated speaking improvement.

All example personal facts are fictional illustrations. In use, the app must ask for missing facts and accept “I don't know” or “I haven't had that experience.”

## 5. Navigation and screen requirements

Keep the interface calm, compact, and focused on practice. Use plain labels and one main action per screen. Avoid an AI dashboard full of scores. Proposed navigation: Practice, Quiet practice, History; Settings is available from the main screen.

| Screen | Required content and actions | Empty or failure behaviour |
|---|---|---|
| First use | Explain voice and quiet options, local storage, processing choices, and limits; choose role and language | Skip optional experience setup; no microphone permission until recording is requested |
| Practice home | Start one question or short session, resume a saved draft, next linked retry | Offer a starter question without demanding history |
| Session setup | Role pack, one or three questions, voice/text preference; optional real experience notes | Unsupported role falls back visibly to general questions |
| Question and recording | Visible question, TTS controls, explicit Record/Stop, elapsed time, save/cancel | Permission denial offers quiet exercises; no automatic recording |
| Answer review | Local playback, transcript, correction action, Submit for feedback and processing disclosure | Poor transcription offers correction or re-recording; retain audio |
| Feedback | One strength, one priority issue, quoted evidence, supported timestamp, replay and retry actions | Explain insufficient evidence; no fabricated issue just to fill a card |
| Segment retry and comparison | Original context, narrow retry prompt, separate recordings and text, compare criterion, optional full-answer retry | If original audio is deleted, explain why comparison is unavailable |
| Quiet practice | One active exercise, answer action, explanation, linked voice retry | With no history, label starter exercises as general rather than personalised |
| History | Date, role/question, mode, attempts, pending work, linked exercise/retry, deletion | Clear empty state; incomplete sessions remain distinct from completed sessions |
| Settings and privacy | Spoken output toggle, data use, processing consent, storage usage, delete session/all data | Explain when remote deletion is pending; deletion remains free |

Quiet mode must stop spoken prompts and feedback immediately and remain silent across navigation and reopening until the user changes it. All spoken content is also readable. Switching modes must preserve the saved answer or exercise.

## 6. Questions, feedback, and honest coaching

Proposed prototype bank: 12 manually reviewed questions covering motivation, teamwork, handling a problem, learning something, and dealing with a customer. Tag each with role, skill, difficulty, and permissible follow-up intent. Validate relevance with intended users before expanding the bank.

Allow at most one relevant follow-up per answer in the prototype. It should reference what the person actually said, for example “Which task did you take responsibility for?” Do not repeatedly ask the same question, infer an employer's private selection criteria, or turn the session into unlimited chat.

Feedback follows a small rubric: relevance to the question, concrete evidence, personal contribution, understandable sequence, and result or learning where relevant. STAR may be offered as a guide for behavioural questions, not imposed on every answer. “Why this job?” needs relevance and truthful motivation rather than an artificial STAR story.

Each issue must contain the affected criterion, an exact transcript quote or an explicit missing-element explanation, why it matters, and one next action. A missing result is not an audible sentence: attach the suggestion to the relevant answer context and label it as missing information instead of inventing a precise “error moment.”

Examples must preserve the user's facts. Rewrites may shorten or clarify existing material; missing facts use a question or visible placeholder, never a made-up percentage, award, responsibility, or achievement. Offer “This feedback is wrong” and transcript correction. Record the report locally for the prototype; transmitting an example for research requires separate consent.

## 7. Loop A: exact moment → replay → focused retry → compare

A feedback card anchors to a specific immutable answer version and, when reliable, one audio segment. The user plays that segment with a small context margin, sees the quote, and retries only the requested part. A retry is a new attempt with its own audio and transcript, not a destructive edit of the original.

The comparison view places Original and Retry in adjacent labelled cards where space permits, or vertically on small screens. Playback is sequential so the recordings do not overlap. Show the shared question and criterion. Display a concrete content difference, not an overall numerical score. Never imply that a shorter recording automatically means a better answer.

The user may retry again, keep the original, dismiss the advice, or record the whole answer. A segment retry does not silently splice audio into a synthetic full answer. History retains the relationship between attempts. A suggested prototype limit of two AI-reviewed retries per answer controls scope and cost; users can always replay saved recordings.

Completion means a saved retry with a valid relationship to the original and an accessible comparison. Improvement is a separate, evidence-based judgement that may be positive, unchanged, or uncertain.

## 8. Loop B: personal weakness → quiet exercise → later voice retry

Generate a short exercise from a supported issue, retaining the source question, quote, answer version, and learning objective. Target roughly one to three minutes. Use constrained exercise templates rather than a blank chat box.

| Exercise | User action | Feedback and return to voice |
|---|---|---|
| Find the irrelevant sentence | Select a sentence in their answer that does not help answer the question | Explain the relationship to the question; permit disagreement; retry the relevant section |
| Shorten rambling wording | Edit their excerpt to preserve the important facts with fewer words | Identify removed repetition and lost facts, if any; retry the shorter explanation |
| Add a missing contribution or result | Write what they personally did or what actually happened | Ask for specificity without fabricating facts; record the completed thought later |
| Choose a real experience | Choose among their own saved experiences and explain the fit to a follow-up | Explain relevance and ask for a concrete detail; launch that question in voice mode |

Implement two templates first: shortening an excerpt and adding a contribution/result. The other two remain defined extensions unless time permits. A dismissed or unreliable issue must not repeatedly generate exercises. Avoid sensitive prompts unrelated to the interview question.

After submission show a brief explanation and “Save for voice practice.” Queue the exact question, edited material, and criterion. Later, start from that context and compare with the original if available. Never force speaking to finish a quiet exercise. Track exercise completed and voice retry completed as separate events. Users without voice history can do clearly labelled starter exercises and optionally connect a later answer; no invented personalised weakness.

## 9. Speech, audio alignment, and uncertainty

Use turn-based Record → Stop → Review → Submit → Feedback. This is sufficient for a spoken interviewer and spoken feedback. Realtime interruptions, full-duplex audio, and animated interviewers are later work.

Android TextToSpeech can speak generated question and feedback text through an installed engine, avoiding a separate paid voice-generation API for this design. Engine availability, installed language/voice data, and offline behaviour must be checked on the device. Provide text and a retry/settings route when speech output is unavailable. Do not describe all engine voices as universally free or offline. [Android TextToSpeech reference](https://developer.android.com/reference/android/speech/tts/TextToSpeech)

Android SpeechRecognizer availability and on-device recognition vary. A default recognizer may stream audio to a remote service; it must not be advertised as automatically private or offline. It is not the sole guarantee of a persisted recording and reliable word timing. Confirm the recording/transcription integration and supported languages on physical devices before choosing it. [Android SpeechRecognizer reference](https://developer.android.com/reference/android/speech/SpeechRecognizer)

The first technical spike must prove that the exact saved audio can be transcribed and aligned. Prefer transcription of the saved file with segment/word timing, or a verified supported audio-input route. Do not assume two simultaneous microphone consumers work. Select the provider only after checking price, participant eligibility, retention, timestamp output, and supported devices. No provider is selected by this PRD.

Store audio duration, file identity, recording version, transcript version, timed tokens/segments, and alignment status. Times use offsets from the start of the exact saved recording. Validate that segment bounds are ordered, inside the recording, and correspond to the cited quote. The model selects evidence from supplied text spans; it must not invent timestamps. Application logic resolves verified spans to audio times.

Transcript edits retain the original recognised text and create a new version. A corrected word is not automatically aligned: mark affected timing uncertain and re-align or disable precise replay for that span. Re-analysis invalidates feedback derived from the previous version. Retries always have independent timing.

If timing is absent or unreliable, show a text quote and full-answer playback labelled “Exact segment unavailable.” Manual user-selected replay ranges may be a disclosed prototype fallback. This preserves useful feedback but does not satisfy validation of automatic timestamped feedback.

Separate objective measurements from coaching. Recording duration is directly measurable; words per minute depends on a usable transcript; pause estimates depend on audio analysis; filler counts depend on correct recognition. Pitch and loudness vary with microphone placement, noise, and recording settings. Do not infer personality, confidence, honesty, employability, emotion, or accent quality from these measurements. Transcript-only feedback cannot assess tone. Basic duration may ship first; advanced pronunciation/prosody assessment is deferred pending independent validation and cost review.

## 10. Session states and recovery

Persist stable progress at each transition. Suggested states: draft, question_ready, recording, recorded_local, transcribing, transcript_review, analysing, feedback_ready, retry_recording, comparison_ready, completed, interrupted, and failed_recoverable. Quiet exercises have ready, editing, submitted, saved_for_voice, and voice_completed states.

| Event | Required recovery |
|---|---|
| Permission denied or no microphone | Offer active quiet practice; allow returning to permission settings voluntarily |
| Silence, clipped input, or noisy audio | Explain recording quality issue, preserve playable audio, offer re-record; abstain from affected findings |
| Call, app backgrounding, or audio-focus loss | Stop recording safely and mark interrupted; never silently resume microphone capture |
| App terminated | Restore last saved stage; identify incomplete audio; do not claim unsaved content survived |
| No network or timeout | Keep local answer, distinguish unsent from processing, offer manual retry; no undisclosed background upload |
| TTS failure | Continue with readable question/feedback; prevent speech from being captured as the answer |
| Duplicate submit or provider response after cancel | Use attempt/version/request IDs; do not create duplicate feedback or overwrite a newer attempt |
| Quota reached | Explain the limit before a paid request; preserve replay, existing exercises, and deletion |
| Invalid or unsupported model output | Reject unsupported quote/span and unsafe structure; allow bounded retry or evidence-unavailable result |
| Storage full | Explain before recording when detectable; preserve prior history and offer selective deletion |
| Delete while remote work is running | Tombstone the attempt, cancel where possible, discard late output and enqueue remote cleanup |

Suggested answer cap: two minutes, with a visible approaching-limit notice and saved recording at the cap. Proposed processing timeout: 45 seconds before offering retry/cancel; this is a UX limit, not a latency promise. Provider retries must be bounded and accounted for, because a timeout does not prove an external request was unbilled.

## 11. Data model and architecture requirements

Prefer a local-first Android client with a small server endpoint for paid AI requests. Kotlin/Compose is a candidate, not a requirement inferred from the old project. Do not modify or reuse existing Sportsnap application code until an implementation plan explicitly chooses a safe approach.

| Entity | Minimum information |
|---|---|
| Practice profile | Optional role, language, real experience notes; no mandatory CV |
| Question | Stable ID, text, role/skill tags, bank version |
| Session | ID, mode, question sequence, created time, state |
| Answer attempt | ID, question/session, parent attempt if retry, local audio reference, duration, transcript/alignment versions, processing state |
| Feedback item | ID, criterion, quote/span or missing-element anchor, validated timing when available, evidence status, next action, source versions |
| Quiet exercise | ID, template, source feedback/attempt, user response, explanation, completion state |
| Retry link | Original attempt/segment, exercise if relevant, new attempt, comparison criterion/result |
| Processing request | Idempotency key, authorised attempt/version, consent scope, status, bounded usage accounting; no private payload in logs |

The server stores credentials, enforces per-user and global quotas, validates requests and structured responses, and checks ownership. Credentials must never ship in the APK. For an accountless demo, an installation credential may limit casual use but is not strong abuse prevention; gate invitations and global spending separately. Store only the context needed for each request.

Keep paid inference outside retryable database transactions. Persist a request result before reusable finalisation; retries must not repeatedly charge without explicit bounds. Model instructions must treat transcripts and experience notes as user data, not executable instructions. Use schema validation and application-side evidence checks.

Local-only history and no login are proposed for the prototype. Cloud sync, account recovery, cross-device access, and analytics dashboards are deferred. Users must be told that losing the device or uninstalling can lose local history.

## 12. Technical foundation and current project setup

The working product name is **PrepSuite**. The implementation repository is the private GitHub repository [`jungwooshim1212/PrepSuite`](https://github.com/jungwooshim1212/PrepSuite). The separate local checkout is `/Users/macintosh/Documents/PrepSuite`; it is the working copy for this product and must not be mixed with the abandoned Sportsnap Android source.

The intended backend project is Supabase project `qtwhzseowgktmocsjwib`, displayed as **PrepSuite**, currently on the Free plan and verified healthy. The repository currently contains only the minimal setup needed to establish the project boundary: `README.md`, `.gitignore`, `supabase/.gitignore`, and the official CLI-generated `supabase/config.toml`. There is no approved database schema, migration, storage bucket, authentication flow, or runtime client connection yet.

The GitHub repository and Supabase project are separate verified resources. The Supabase dashboard has not yet confirmed its GitHub repository integration: the attempted authorization opened a blank popup and timed out. This PRD must not describe that integration as complete. The next integration gate is to connect the exact private `PrepSuite` repository to the exact Supabase project and verify the repository identity in the dashboard.

### Intended architecture

- Android is the first client. Kotlin/Compose remains a candidate; the framework is an open implementation decision until the build plan confirms it.
- GitHub is the source of truth for application code, migrations, configuration templates, and reviewable documentation.
- Supabase is an intended backend for optional authentication, Postgres data, consented storage, and narrowly scoped server-side functions. The local-first prototype should work without Supabase whenever the feature does not require remote processing or sync.
- A future server-side function or separate backend may proxy paid AI requests. Provider keys and Supabase service-role keys must remain server-side and must never be embedded in the Android APK, committed to Git, or exposed in client logs.
- The public Supabase anon/publishable key may be used by the client only with deliberate Row Level Security (RLS), least-privilege policies, and no assumption that the key is secret. Development, staging, and production projects/keys must be separated before real user data is used.
- Raw audio remains local by default. A Supabase Storage bucket is a later opt-in capability requiring explicit consent, retention rules, access policies, and deletion handling. Do not upload audio merely because a Supabase project exists.

### First backend slice after connection

These are proposed entities for a later, approved migration—not an implemented schema: `profiles`, `practice_sessions`, `answer_attempts`, `feedback_items`, and `quiet_exercises`, with ownership columns and RLS policies. Audio objects should be represented only when the user has opted into cloud storage; otherwise an attempt stores a local reference and metadata. Keep provider request records free of raw audio, private transcript bodies, and prompt payloads wherever possible.

The first remote test should be deliberately small: connect the client using a non-service key, read or write one test record under RLS, verify that another user cannot access it, and confirm that the app remains usable when the backend is unavailable. No production migration, deployment, sync, or data import is authorised by this PRD.

### Integration acceptance criteria

1. The Supabase dashboard identifies the exact `jungwooshim1212/PrepSuite` repository and the exact project ref above, with authorization status visible.
2. The local client can reach a deliberately minimal test path using a client-safe key and an RLS policy; a failed connection leaves local practice, playback, deletion, and quiet exercises usable.
3. A repository scan finds no Supabase service-role key, AI provider key, raw audio, private transcript, or signed media URL in tracked files, build output, or logs.
4. Any migration is reviewed, reproducible from a clean checkout, and explicitly separated by environment before real participant data is accepted.
5. The dashboard, local checkout, and release notes distinguish repository integration from runtime app connectivity; completing one does not imply the other.

## 13. Privacy, deletion, and accessibility

Before first recording, explain that audio will be saved for replay and ask for recording permission. Before remote transcription or LLM processing, explain exactly which audio/text goes to which service, for what purpose, with what retention. Require affirmative consent for that scope. An OS microphone permission is not consent to cloud processing. Do not upload by default before disclosure and consent. Distinguish optional research sharing from processing needed for the requested feedback.

Keep raw recordings in app-private local storage by default, outside ordinary shared media access. Explicitly configure backup behaviour so sensitive audio/transcripts are not unexpectedly included in cloud device backups. Use platform-supported protection and TLS in transit. Never log raw audio, transcripts, personal examples, signed media URLs, or prompt bodies in analytics/crash reports.

Proposed retention: local history remains until deletion, with visible storage usage and per-session/all-data deletion. The service should remove its temporary audio/text after processing and within a documented maximum of 24 hours. This is a product target, not a verified provider guarantee; beta cannot promise it unless the chosen provider and infrastructure support it. Document separate provider abuse-log and backup retention before real data use.

Deletion removes audio, transcript, feedback, exercises, and retry links derived from the deleted session. If a user keeps other independent sessions, remove broken references rather than deleting unrelated work. Remote cleanup that cannot finish immediately displays pending status and retries without recreating local content. Do not promise instantaneous erasure from immutable provider backups.

Confirm actual audience ages, launch region, service terms, publisher eligibility, and any necessary adult involvement before the real-user pilot. Do not assume a service permits student/minor use. Public release needs a privacy policy and accurate store data disclosures reflecting actual processing. These are unresolved release decisions, not legal conclusions from this document.

Accessibility: support TalkBack labels, large font sizes, adequate contrast, visible focus and generous touch targets, text for all spoken output, and controls that do not depend only on colour, waveforms, or gestures. Allow typing and active exercises without microphone access. Use a visible elapsed timer rather than a punitive speed score. A person who cannot speak can complete quiet practice independently; speaking progress simply remains unmeasured.

## 14. Scope and proposed delivery plan

| Stage | Included | Exit condition |
|---|---|---|
| Planning now | This PRD, open decisions, future technical spike design | Claude produces a bounded plan; no code assumed authorised |
| Days 1–2 after build approval | One target role/language, consent flow, saved audio, TTS, transcription/alignment spike | Exact saved-file replay and supported timing demonstrated on target devices |
| Days 3–5 | Reviewed question bank, one-answer feedback, transcript review, local history | One truthful evidence-linked feedback loop works and survives interruption |
| Days 6–8 | Segment retry, original/retry comparison, two quiet exercise templates and linked queue | Both loops complete end to end |
| Days 9–10 | Recovery, deletion, accessibility checks, cost limits, small usability walkthrough | Core acceptance cases pass; remaining limitations documented |
| Following pilot | Observe intended users, fix blockers, assess return use and costs | Decide whether to invest in production and monetisation |

“One to two weeks” is a prototype estimate for an experienced solo student builder, not a guaranteed production launch. If alignment is not solved by the initial spike, narrow to a disclosed manual-segment demo or extend the schedule. Do not remove the two loops and still call the intended product validated. Cut question breadth, follow-ups, and visual polish before privacy, recovery, or the core learning relationship.

Later: additional roles/languages, more quiet templates, optional cloud history, independently evaluated delivery measures, pronunciation services, longer mock interviews, and interruption-capable realtime speech. Add only after demand and cost evidence.

For qualifying new personal Google Play developer accounts, the current documented production-access process includes a closed test with at least 12 opted-in testers for 14 continuous days followed by an application for production access. This can extend public release beyond the prototype estimate; satisfying the duration does not guarantee approval. Verify applicability to the actual publisher account before scheduling. [Google Play testing requirements](https://support.google.com/googleplay/android-developer/answer/14151465)

## 15. Acceptance and validation

The following are proposed measurable gates, not results already achieved.

| ID | Acceptance case |
|---|---|
| A1 | New user completes a one-question voice session and opens saved feedback/history without creating an account in the prototype |
| A2 | Every displayed precise timestamp has valid in-bounds timing tied to the cited answer version; unsupported timing falls back visibly |
| A3 | On 20 consented test excerpts across supported devices/accents, at least 18 automatically selected replay ranges contain the complete cited phrase without truncating it; report excluded cases and fallback rate separately |
| A4 | A focused retry leaves original bytes unchanged and plays both attempts independently; question/criterion remain visible |
| A5 | Each of the two MVP quiet templates accepts an active response, explains it, and creates a voice retry linked to the correct source |
| A6 | Completing a quiet exercise never marks a voice retry complete; the later recording updates the linked history correctly |
| A7 | Quiet mode produces no app-initiated speech after switching, including navigation and reopening; microphone denial does not block quiet work |
| A8 | Transcript correction cannot leave stale precise feedback attached to a changed span; affected alignment is revalidated or disabled |
| A9 | A reviewed set of 20 answer/feedback examples contains no fabricated user facts, unsupported precise claims, or personality/employability scores; any failure blocks pilot expansion |
| A10 | No-network, timeout, duplicate-submit, process restart, call interruption, and storage-failure cases preserve prior saved attempts and show truthful states |
| A11 | Deleting a session removes its local content and derived links; remote deletion is verified where remote storage exists; late responses cannot restore it |
| A12 | Network inspection confirms no private audio/text transfer before relevant consent; logs and crash reports contain no private payload |
| A13 | Quota tests prevent new paid requests at the configured limit while keeping replay/deletion available; actual provider usage is reconciled with request records |
| A14 | On supported physical devices, question output is not recorded as the answer; TTS unavailable and recognition unavailable have working text/quiet paths |
| A15 | Main flows remain usable with TalkBack and enlarged text without clipped primary actions |

A3 is a preliminary prototype target, not a statistically reliable accuracy claim. Manually annotate reference excerpts before evaluation, separate tuning and evaluation examples, and review the failures rather than averaging away accent or device problems. If fallback is frequent, report that the distinctive automatic feature remains unproven.

Proposed discovery: interview five reachable first-time applicants about a recent application and how they practised. Then observe five to ten consenting pilot participants completing both loops. If feasible, compare their experience with their usual chatbot/manual practice approach using the same question; this tests workflow preference, not superior model intelligence.

Measure counts with denominators: started/submitted sessions, feedback replayed, focused retries completed, quiet exercises completed, linked voice retries later completed, voluntary return within seven days, incorrect-feedback reports, and processing cost per completed loop. Distinguish researcher-prompted use from voluntary use. Do not transmit answer content for analytics.

Proposed pilot decision targets: at least four of five observed users complete both loops without step-by-step help; at least three can explain why the linked workflow is useful; at least three of ten pilot users return voluntarily within seven days. Small samples guide interviews and iteration rather than prove retention. If users only want generic questions, simplify or reconsider the differentiation before expanding.

## 16. Costs and monetisation hypotheses

The first prototype is free and invitation-limited. Use installed TTS where supported, local playback/storage, short answers, small prompt context, bounded retries, and cached feedback for an unchanged attempt. On-device recognition may reduce costs on supported devices; free provider tiers are development allowances, not a promise of free production.

Estimate cost per completed loop as transcription minutes × selected rate + LLM input/output usage + retry overhead + temporary storage/transfer + service overhead. Model failed attempts separately. Use current provider prices only after provider selection; this document does not invent a dollar cost. Record aggregate usage without private content and reconcile with bills. Set an owner-approved monthly subsidy before inviting users; alerts alone are not a hard spending cap.

Candidate business model: limited free analysed answers with paid practice packs or a capped monthly allowance. Unlimited lifetime AI for a tiny one-off price may be unsustainable. A one-time offline question-pack purchase could be tested separately from recurring cloud usage. Exact price and allowance remain open. Always retain access to already-saved personal recordings, deletion, and privacy controls without payment.

Test willingness to pay after users experience replay and a useful retry: ask what they would pay for a short period before an interview, then validate with a real offer only once billing, eligibility, and service costs are ready. Do not count hypothetical willingness or a waitlist as revenue. Production monetisation must use an appropriate compliant billing route verified at implementation time; no billing implementation is part of this request.

## 17. Open decisions for the next planning pass

| Decision | Proposed default or required next step |
|---|---|
| Product name | Keep Interview Practice App until a name is selected and checked |
| First users, age range, region | Recruit a reachable first-job group; confirm eligibility before real-data processing |
| First role and language | English, general plus one customer-facing role; verify with discovery |
| Publisher/provider account ownership | Establish eligible account holder and budget responsibility |
| Recording/transcription provider | Benchmark exact-file timing, supported devices, consent/retention, and total cost in the initial spike |
| Android support range and devices | Select after checking available test hardware; include a lower-end physical device and different microphone conditions |
| Accounts and storage | Local history without login for prototype; do not add sync by default |
| Prototype limits | Propose three-question sessions, two-minute answers, two reviewed retries; adjust after observing use |
| Monthly spend ceiling | Owner must choose before paid real-user processing; implement global admission limits |
| Release date and paid offering | Set after prototype evidence and publisher-specific Play requirements |

Claude's next deliverable should be a dependency-ordered build plan, a narrow technical spike for audio alignment, selected data-flow/consent design, cost worksheet inputs, and a test plan mapped to A1–A15. Clearly surface unresolved choices. Do not resurrect old product features or assume this PRD authorises application changes.

## 18. Mature naming directions

Keep the document and product working title **Interview Practice App** until a name is selected. The owner prefers a mature, understated name. These are brainstorming directions only; none is selected or checked for trademarks, app-store availability, domains, or uniqueness.

| Name | Intended feel and tradeoff |
|---|---|
| Poise | Composed and concise; positioning must avoid promising measurable confidence |
| Cadence | Suggests spoken practice and repetition; may imply delivery coaching more than answer content |
| Bearing | Professional presence and direction; less immediately descriptive of interview practice |
| Articulate | Clear connection to expressing ideas; could sound like a language-learning product |
| Rehearsal | Direct, mature description of preparation; broader than interviews |
| Forum | Serious and conversational; broad enough that the product purpose needs a subtitle |

Test which name intended users understand and remember alongside a plain subtitle such as “Interview practice.” Do not rename application IDs or purchase anything until a name is chosen and checked.
