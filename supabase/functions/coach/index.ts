// PrepSuite coach: the one HTTP service between the app and its AI provider.
//
// Runs unchanged locally (`deno run`, see tools/coach/run-local.sh) and as a
// Supabase Edge Function. Audio never reaches this service: the app sends the
// on-device transcript plus delivery numbers and gets short JSON back.
//
//   POST /coach   {"action": "questions" | "feedback" | "wrapup" | "ask", ...}
//   GET  /health  {"ok": true, "mock": <bool>}
//
// COACH_MOCK=1 explicitly enables deterministic demo responses. Missing
// credentials never silently substitute those responses for live AI.

import Anthropic from "npm:@anthropic-ai/sdk@0.128.0";
import { mockAsk, mockFeedback, mockQuestions, mockWrapup } from "./mock.ts";
import { deliverySummary } from "./delivery.ts";
import { createOllamaProvider } from "./ollama.ts";
import {
  clientKey,
  corsHeaders,
  DAY,
  DEFAULT_LIMITS,
  isJson,
  isLoopback,
  MINUTE,
  type RateLimits,
  SECURITY_HEADERS,
  TOKEN_HEADER,
  tokenDigest,
  tokenMatches,
  Windows,
} from "./security.ts";
import {
  ASK_SCHEMA,
  ASK_SYSTEM,
  type AskFeedback,
  type AskInput,
  type AskResult,
  type Delivery,
  FEEDBACK_SCHEMA,
  FEEDBACK_SYSTEM,
  type FeedbackInput,
  type FeedbackResult,
  MODEL,
  QUESTIONS_SCHEMA,
  QUESTIONS_SYSTEM,
  type QuestionsInput,
  type QuestionsResult,
  WRAPUP_SCHEMA,
  WRAPUP_SYSTEM,
  type WrapupAnswer,
  type WrapupInput,
  type WrapupResult,
} from "./prompts.ts";

export const LIMITS = {
  job: 300,
  question: 400,
  transcript: 6000,
  answers: 10,
  count: { min: 1, max: 8, default: 5 },
  feedbackText: 1000, // headline / problem / delivery (or fix) echoed back in wrap-up and ask
  userQuestion: 500,
  askReplyWords: 110, // hard cap on the spoken ask reply; the prompt asks for at most 80
  bodyBytes: 200_000,
} as const;

export type Route = "questions" | "feedback" | "wrapup" | "ask";

export interface RouteSpec {
  system: string;
  schema: Record<string, unknown>;
  effort: "low" | "medium" | "high";
  /** Cap on the visible JSON reply. Claude gets THINKING_ROOM on top of it. */
  maxTokens: number;
}

/** Adaptive thinking counts against max_tokens, so Claude's cap leaves room to think before replying. */
export const THINKING_ROOM = 12_000;

/** On a safety-classifier decline, the API re-runs the request on the model recommended for that category. */
const FALLBACK_BETA = "server-side-fallback-2026-07-01";

const ROUTES: Record<Route, RouteSpec> = {
  // low: a short, well-specified list right after the 10 s recording; the user is watching a spinner.
  questions: { system: QUESTIONS_SYSTEM, schema: QUESTIONS_SCHEMA, effort: "low", maxTokens: 3072 },
  // medium: the core judgement (one biggest problem, exact quote, number-grounded delivery) needs some thinking, but it runs after every answer.
  feedback: { system: FEEDBACK_SYSTEM, schema: FEEDBACK_SCHEMA, effort: "medium", maxTokens: 2048 },
  // medium: synthesis across up to 10 answers under a no-invented-facts rule; runs once per session.
  wrapup: { system: WRAPUP_SYSTEM, schema: WRAPUP_SCHEMA, effort: "medium", maxTokens: 3072 },
  // low: a few spoken sentences mid-practice while the person waits. The reply is about 150
  // tokens; Ollama spends this as num_predict with thinking off, so 1024 is ample headroom.
  ask: { system: ASK_SYSTEM, schema: ASK_SCHEMA, effort: "low", maxTokens: 1024 },
};

/** The slice of the Anthropic client this service uses (tests pass a fake). */
export interface ClaudeClient {
  beta: {
    messages: {
      create(params: Anthropic.Beta.Messages.MessageCreateParamsNonStreaming): PromiseLike<Anthropic.Beta.Messages.BetaMessage>;
    };
  };
}

export interface CoachProvider {
  name: string;
  model: string;
  /** The provider can send transcripts and metrics outside this computer. */
  cloud: boolean;
  generate(route: Route, spec: RouteSpec, prompt: string, log: Logger): Promise<unknown>;
}

export type Logger = (entry: Record<string, unknown>) => void;

type ErrorCode = "bad_request" | "unauthorized" | "upstream" | "rate_limited" | "not_configured";

export class CoachError extends Error {
  constructor(readonly status: number, readonly code: ErrorCode, message: string) {
    super(message);
  }
}

function bad(message: string): never {
  throw new CoachError(400, "bad_request", message);
}

function badShape(): never {
  throw new CoachError(502, "upstream", "The AI reply could not be read. Try again.");
}

// ---------------------------------------------------------------------------
// Input validation
// ---------------------------------------------------------------------------

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

interface TextOpts {
  required?: boolean;
  allowEmpty?: boolean;
  label?: string;
}

function text(obj: Record<string, unknown>, key: string, max: number, opts: TextOpts = {}): string {
  const { required = true, allowEmpty = false, label = key } = opts;
  const v = obj[key];
  if (v === undefined || v === null) {
    if (required) bad(`"${label}" is required.`);
    return "";
  }
  if (typeof v !== "string") bad(`"${label}" must be a string.`);
  // deno-lint-ignore no-control-regex
  const s = v.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, "").trim();
  if (s.length > max) bad(`"${label}" is too long (${s.length} characters, max ${max}).`);
  if (!allowEmpty && s.length === 0) bad(`"${label}" must not be empty.`);
  return s;
}

function num(d: Record<string, unknown>, key: string, min: number, max: number): number {
  const v = d[key];
  if (typeof v !== "number" || !Number.isFinite(v)) bad(`"delivery.${key}" must be a number.`);
  if (v < min || v > max) bad(`"delivery.${key}" must be between ${min} and ${max}.`);
  if (["words", "pauses_over_1s", "filler_count"].includes(key) && !Number.isInteger(v)) {
    bad(`"delivery.${key}" must be a whole number.`);
  }
  return v;
}

function numOrNull(d: Record<string, unknown>, key: string, min: number, max: number): number | null {
  return d[key] === null || d[key] === undefined ? null : num(d, key, min, max);
}

function bool(d: Record<string, unknown>, key: string): boolean {
  const v = d[key];
  if (typeof v !== "boolean") bad(`"delivery.${key}" must be true or false.`);
  return v;
}

function boolOrNull(d: Record<string, unknown>, key: string): boolean | null {
  return d[key] === null || d[key] === undefined ? null : bool(d, key);
}

function parseDelivery(v: unknown): Delivery | null {
  if (v === undefined || v === null) return null;
  if (!isRecord(v)) bad(`"delivery" must be an object.`);
  const rawFillers = v.fillers ?? {};
  if (!isRecord(rawFillers)) bad(`"delivery.fillers" must be an object like {"um": 3}.`);
  const entries = Object.entries(rawFillers);
  if (entries.length > 30) bad(`"delivery.fillers" has too many entries (max 30).`);
  for (const [word, count] of entries) {
    if (word.length > 30) bad(`"delivery.fillers" keys must be at most 30 characters.`);
    if (typeof count !== "number" || !Number.isInteger(count) || count < 0 || count > 10000) {
      bad(`"delivery.fillers.${word}" must be a count.`);
    }
  }
  return {
    duration_s: num(v, "duration_s", 0, 3600),
    words: num(v, "words", 0, 100_000),
    wpm: num(v, "wpm", 0, 1000),
    pauses_over_1s: num(v, "pauses_over_1s", 0, 10_000),
    longest_pause_s: num(v, "longest_pause_s", 0, 3600),
    filler_count: num(v, "filler_count", 0, 10_000),
    fillers: Object.fromEntries(entries) as Record<string, number>,
    loudness_db_mean: num(v, "loudness_db_mean", -200, 50),
    loudness_db_sd: num(v, "loudness_db_sd", 0, 200),
    trailing_off: bool(v, "trailing_off"),
    pitch_hz_mean: numOrNull(v, "pitch_hz_mean", 0, 5000),
    pitch_semitone_sd: numOrNull(v, "pitch_semitone_sd", 0, 100),
    monotone: boolOrNull(v, "monotone"),
    speech_ratio: num(v, "speech_ratio", 0, 1),
  };
}

function parseQuestions(body: Record<string, unknown>): QuestionsInput {
  const job = text(body, "job", LIMITS.job);
  const c = body.count ?? LIMITS.count.default;
  if (typeof c !== "number" || !Number.isInteger(c) || c < LIMITS.count.min || c > LIMITS.count.max) {
    bad(`"count" must be a whole number from ${LIMITS.count.min} to ${LIMITS.count.max}.`);
  }
  return { job, count: c };
}

function parseFeedback(body: Record<string, unknown>): FeedbackInput {
  return {
    job: text(body, "job", LIMITS.job, { required: false, allowEmpty: true }),
    question: text(body, "question", LIMITS.question),
    transcript: text(body, "transcript", LIMITS.transcript, { allowEmpty: true }),
    delivery: parseDelivery(body.delivery),
  };
}

function parseWrapup(body: Record<string, unknown>): WrapupInput {
  const answers = body.answers;
  if (!Array.isArray(answers)) bad(`"answers" must be a list.`);
  if (answers.length < 1 || answers.length > LIMITS.answers) bad(`"answers" must have 1 to ${LIMITS.answers} items.`);
  return {
    job: text(body, "job", LIMITS.job, { required: false, allowEmpty: true }),
    answers: answers.map((a: unknown, i: number): WrapupAnswer => {
      if (!isRecord(a)) bad(`"answers[${i}]" must be an object.`);
      const optional = (key: string) =>
        text(a, key, LIMITS.feedbackText, { required: false, allowEmpty: true, label: `answers[${i}].${key}` });
      return {
        question: text(a, "question", LIMITS.question, { label: `answers[${i}].question` }),
        transcript: text(a, "transcript", LIMITS.transcript, { allowEmpty: true, label: `answers[${i}].transcript` }),
        headline: optional("headline"),
        problem: optional("problem"),
        delivery: optional("delivery"),
      };
    }),
  };
}

function parseAsk(body: Record<string, unknown>): AskInput {
  const userQuestion = text(body, "user_question", LIMITS.userQuestion);
  let feedback: AskFeedback | null = null;
  if (body.feedback !== undefined && body.feedback !== null) {
    const fb = body.feedback;
    if (!isRecord(fb)) bad(`"feedback" must be an object with "headline", "problem" and "fix".`);
    const optional = (key: string) =>
      text(fb, key, LIMITS.feedbackText, { required: false, allowEmpty: true, label: `feedback.${key}` });
    feedback = { headline: optional("headline"), problem: optional("problem"), fix: optional("fix") };
    if (!feedback.headline && !feedback.problem && !feedback.fix) feedback = null;
  }
  return {
    job: text(body, "job", LIMITS.job, { required: false, allowEmpty: true }),
    user_question: userQuestion,
    question: text(body, "question", LIMITS.question, { required: false, allowEmpty: true }),
    answer: text(body, "answer", LIMITS.transcript, { required: false, allowEmpty: true }),
    feedback,
  };
}

// ---------------------------------------------------------------------------
// Prompts: user text is untrusted data inside delimited tags
// ---------------------------------------------------------------------------

/** Angle brackets in user text are swapped so it can never open or close a tag. */
function data(s: string): string {
  return s.replace(/</g, "‹").replace(/>/g, "›");
}

function wordCount(s: string): number {
  const t = s.trim();
  return t ? t.split(/\s+/).length : 0;
}

function questionsPrompt(i: QuestionsInput): string {
  return `Write ${i.count} question${i.count === 1 ? "" : "s"}.\n\n<job>\n${data(i.job)}\n</job>`;
}

function feedbackPrompt(i: FeedbackInput): string {
  const words = wordCount(i.transcript);
  let metrics = "none sent";
  if (i.delivery) {
    const minutes = i.delivery.duration_s / 60;
    const perMinute = minutes > 0 ? Math.round((i.delivery.filler_count / minutes) * 10) / 10 : null;
    metrics = data(JSON.stringify({ ...i.delivery, fillers_per_minute: perMinute }));
  }
  return [
    `<job>\n${data(i.job) || "(not given)"}\n</job>`,
    `<question>\n${data(i.question)}\n</question>`,
    `<transcript>\n${data(i.transcript) || "(empty)"}\n</transcript>`,
    `<delivery_metrics>\n${metrics}\n</delivery_metrics>`,
    `The transcript has ${words} word${words === 1 ? "" : "s"}.`,
  ].join("\n\n");
}

function wrapupPrompt(i: WrapupInput): string {
  const answers = i.answers.map((a, n) =>
    [
      `<answer number="${n + 1}">`,
      `<question>\n${data(a.question)}\n</question>`,
      `<transcript>\n${data(a.transcript) || "(empty)"}\n</transcript>`,
      `<feedback_given>\nheadline: ${data(a.headline) || "(none)"}\nproblem: ${
        data(a.problem) || "(none)"
      }\ndelivery: ${data(a.delivery) || "(none)"}\n</feedback_given>`,
      `</answer>`,
    ].join("\n")
  );
  return `<job>\n${data(i.job) || "(not given)"}\n</job>\n\n<answers>\n${answers.join("\n\n")}\n</answers>`;
}

function askPrompt(i: AskInput): string {
  const fb = i.feedback;
  const feedback = fb
    ? `headline: ${data(fb.headline) || "(none)"}\nproblem: ${data(fb.problem) || "(none)"}\nfix: ${
      data(fb.fix) || "(none)"
    }`
    : "(none)";
  // Context first; the question to answer comes last.
  return [
    `<job>\n${data(i.job) || "(not given)"}\n</job>`,
    `<interview_question>\n${data(i.question) || "(none)"}\n</interview_question>`,
    `<their_answer>\n${data(i.answer) || "(none)"}\n</their_answer>`,
    `<feedback_given>\n${feedback}\n</feedback_given>`,
    `<user_question>\n${data(i.user_question)}\n</user_question>`,
  ].join("\n\n");
}

// ---------------------------------------------------------------------------
// Claude call
// ---------------------------------------------------------------------------

async function callClaude(client: ClaudeClient, route: Route, userContent: string, log: Logger, model = MODEL): Promise<unknown> {
  const spec = ROUTES[route];
  const started = Date.now();
  const message = await client.beta.messages.create({
    model,
    max_tokens: spec.maxTokens + THINKING_ROOM,
    thinking: { type: "adaptive" },
    output_config: { effort: spec.effort, format: { type: "json_schema", schema: spec.schema } },
    system: [{ type: "text", text: spec.system, cache_control: { type: "ephemeral" } }],
    messages: [{ role: "user", content: userContent }],
    betas: [FALLBACK_BETA],
    fallbacks: "default",
  });

  log({
    event: "claude",
    route,
    ms: Date.now() - started,
    served_by: message.model,
    stop: message.stop_reason,
    input_tokens: message.usage.input_tokens,
    output_tokens: message.usage.output_tokens,
    cache_read_tokens: message.usage.cache_read_input_tokens ?? 0,
  });

  if (message.stop_reason === "refusal") {
    throw new CoachError(502, "upstream", "The AI could not respond to this one. Try again with a different answer.");
  }
  if (message.stop_reason === "max_tokens") {
    throw new CoachError(502, "upstream", "The AI reply was cut off. Try again.");
  }

  if (message.stop_reason !== "end_turn") badShape();
  // Thinking blocks carry no reply text. After a fallback, the reply is what follows the last switch point.
  const lastSwitch = message.content.findLastIndex((b) => b.type === "fallback");
  const json = message.content
    .slice(lastSwitch + 1)
    .map((b) => (b.type === "text" ? b.text : ""))
    .join("");
  try {
    return JSON.parse(json);
  } catch {
    badShape();
  }
}

export function createClaudeProvider(client: ClaudeClient, model = MODEL): CoachProvider {
  return {
    name: "anthropic", model, cloud: true,
    generate: (route, _spec, prompt, log) => callClaude(client, route, prompt, log, model),
  };
}

// ---------------------------------------------------------------------------
// Output clean-up: enforce the contract even if the model drifts
// ---------------------------------------------------------------------------

function clean(v: unknown, maxWords?: number): string {
  if (typeof v !== "string") return "";
  let t = v
    .replace(/\p{Extended_Pictographic}️?/gu, "")
    .replace(/\s*—\s*/g, ", ") // no em dashes
    .replace(/\s+–\s+/g, ", ")
    .replace(/–/g, "-")
    .replace(/\s+/g, " ")
    .replace(/\s+([,.;:!?])/g, "$1")
    .replace(/[,;:](?=[,.;:!?])/g, "")
    .replace(/^[,;:\s]+/, "")
    .trim();
  if (maxWords) {
    const words = t.split(" ");
    if (words.length > maxWords) t = words.slice(0, maxWords).join(" ").replace(/[,;:]$/, "");
  }
  return t;
}

function matchKey(s: string): string {
  return s.normalize("NFKC").toLowerCase().replace(/[‘’]/g, "'").replace(/[^\p{L}\p{N}']+/gu, " ").trim();
}

/** Keep a quote only if it really is in the transcript (ignoring case and punctuation). */
export function verifiedQuote(quote: string, transcript: string): string {
  const q = clean(quote).replace(/^["'“”‘’]+|["'“”‘’]+$/g, "").trim();
  const parts = q.split(/\.\.\.|…/).map(matchKey).filter(Boolean);
  if (!parts.length) return "";
  const haystack = ` ${matchKey(transcript)} `;
  let after = 0;
  for (const part of parts) {
    const found = haystack.indexOf(` ${part} `, after);
    if (found < 0) return "";
    after = found + part.length + 1;
  }
  return q;
}

function outputText(v: unknown, max: number, allowEmpty = false): string {
  if (typeof v !== "string" || v.length > max) badShape();
  const result = clean(v);
  if (!allowEmpty && !result) badShape();
  return result;
}

function normalizeQuestions(raw: unknown, input: QuestionsInput): QuestionsResult {
  if (!isRecord(raw) || !Array.isArray(raw.questions)) badShape();
  const seen = new Set<string>();
  const items: { text: string; focus: string }[] = [];
  const add = (t: string, focus: string) => {
    if (!t || seen.has(t.toLowerCase())) return;
    seen.add(t.toLowerCase());
    items.push({ text: t, focus });
  };
  if (raw.questions.length !== input.count) badShape();
  for (const q of raw.questions) {
    if (!isRecord(q)) badShape();
    add(outputText(q.text, LIMITS.question), clean(outputText(q.focus, 120), 8));
  }
  if (items.length !== input.count) badShape();
  return {
    job_title: clean(outputText(raw.job_title, 160), 12),
    questions: items.map((q, i) => ({ id: `q${i + 1}`, ...q })),
  };
}

function normalizeFeedback(raw: unknown, input: FeedbackInput): FeedbackResult {
  if (!isRecord(raw)) badShape();
  const evidence = outputText(raw.evidence, 400, true);
  const verifiedEvidence = verifiedQuote(evidence, input.transcript);
  if (evidence && !verifiedEvidence) badShape();
  const out: FeedbackResult = {
    headline: clean(outputText(raw.headline, 200), 12),
    problem: outputText(raw.problem, LIMITS.feedbackText),
    evidence: verifiedEvidence,
    fix: outputText(raw.fix, LIMITS.feedbackText),
    // Acoustic feedback is reproducible from measurements. A model cannot
    // invent hearing a typed answer or infer emotions from pitch or volume.
    delivery: deliverySummary(input.delivery),
    strength: outputText(raw.strength, 500),
  };
  if (!out.headline || !out.problem || !out.fix) badShape();
  return out;
}

function list(v: unknown, min: number, max: number): string[] {
  if (!Array.isArray(v) || v.length < min || v.length > max) badShape();
  return v.map((s) => outputText(s, 500));
}

function normalizeWrapup(raw: unknown, input: WrapupInput): WrapupResult {
  if (!isRecord(raw)) badShape();
  if (!Array.isArray(raw.stories_to_use) || raw.stories_to_use.length > 3) badShape();
  const stories = raw.stories_to_use.map((story) => {
    if (!isRecord(story) || !Number.isInteger(story.answer_index)) badShape();
    const index = story.answer_index as number;
    if (index < 1 || index > input.answers.length) badShape();
    const quote = outputText(story.evidence, 500);
    const verified = verifiedQuote(quote, input.answers[index - 1].transcript);
    if (!verified) badShape();
    // Display their own words instead of unverified AI embellishment.
    return `Question ${index}: "${verified}"`;
  });
  const out: WrapupResult = {
    tips: list(raw.tips, 3, 5),
    last_minute_notes: list(raw.last_minute_notes, 3, 6),
    stories_to_use: stories,
  };
  if (!out.tips.length || !out.last_minute_notes.length) badShape();
  return out;
}

/** Drops markdown a text-to-speech voice would read out, and ends list lines as sentences. */
function forSpeech(s: string): string {
  return s
    .replace(/^[ \t]*(?:#{1,6}|[-*•]|\d{1,2}[.)])[ \t]+/gm, "")
    .replace(/\*\*|__|[*`]/g, "")
    .replace(/([\p{L}\p{N}"'”’)])[ \t\r]*\n+/gu, "$1.\n");
}

/** At most `max` words, cut back to the last full sentence when that keeps most of it. */
function capWords(t: string, max: number): string {
  const words = t.split(" ");
  if (words.length <= max) return t;
  const cut = words.slice(0, max).join(" ");
  const sentences = /^.*[.!?](?=\s|$)/.exec(cut)?.[0];
  if (sentences && sentences.split(" ").length >= max / 2) return sentences;
  return `${cut.replace(/[,;:.!?]+$/, "")}.`;
}

function normalizeAsk(raw: unknown): AskResult {
  if (!isRecord(raw) || typeof raw.answer !== "string" || raw.answer.length > 3000) badShape();
  const answer = capWords(clean(forSpeech(raw.answer)), LIMITS.askReplyWords);
  if (!/[\p{L}\p{N}]/u.test(answer)) badShape();
  return { answer };
}

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

function toCoachError(err: unknown, log: Logger): CoachError {
  if (err instanceof CoachError) return err;
  let e: CoachError;
  // Most specific first: the SDK's connection errors are subclasses of APIError.
  if (err instanceof Anthropic.NotFoundError) {
    e = new CoachError(502, "upstream", "The AI model is not available right now.");
  } else if (err instanceof Anthropic.RateLimitError) {
    e = new CoachError(429, "rate_limited", "The AI is busy right now. Wait a few seconds and try again.");
  } else if (err instanceof Anthropic.AuthenticationError || err instanceof Anthropic.PermissionDeniedError) {
    e = new CoachError(503, "not_configured", "The AI key on the server is missing or not valid.");
  } else if (err instanceof Anthropic.APIConnectionTimeoutError) {
    e = new CoachError(504, "upstream", "The AI took too long to answer. Try again.");
  } else if (err instanceof Anthropic.APIConnectionError) {
    e = new CoachError(502, "upstream", "Could not reach the AI service. Try again.");
  } else if (err instanceof Anthropic.APIError) {
    if (err.status === 402) e = new CoachError(503, "not_configured", "The AI account has run out of credit.");
    else if (err.status === 529) {
      e = new CoachError(503, "upstream", "The AI service is overloaded. Try again in a moment.");
    } else e = new CoachError(502, "upstream", "The AI service returned an error. Try again.");
  } else {
    e = new CoachError(502, "upstream", "Something went wrong. Try again.");
  }
  log({
    event: "error",
    code: e.code,
    status: e.status,
    upstream_status: err instanceof Anthropic.APIError ? err.status ?? null : null,
    request_id: err instanceof Anthropic.APIError ? err.requestID ?? null : null,
    // Never log provider error bodies, prompts, transcripts or credentials.
    error_type: err instanceof Error ? err.name : "unknown",
  });
  return e;
}

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------

function json(status: number, body: unknown, headers: Record<string, string>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...headers, "content-type": "application/json; charset=utf-8" },
  });
}

/** "/functions/v1/coach/health/" -> "/coach/health"; "" -> "/". */
function routePath(pathname: string): string {
  const p = pathname.replace(/\/+$/, "").replace(/^\/functions\/v1(?=\/|$)/, "");
  return p || "/";
}

async function readJson(req: Request): Promise<Record<string, unknown>> {
  if (Number(req.headers.get("content-length") ?? 0) > LIMITS.bodyBytes) bad("Request body is too large.");
  const reader = req.body?.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  if (reader) {
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > LIMITS.bodyBytes) {
          await reader.cancel();
          bad("Request body is too large.");
        }
        chunks.push(value);
      }
    } finally {
      reader.releaseLock();
    }
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  const raw = new TextDecoder().decode(bytes);
  let body: unknown = undefined;
  try {
    body = JSON.parse(raw);
  } catch {
    bad("Body must be valid JSON.");
  }
  if (!isRecord(body)) bad("Body must be a JSON object.");
  return body;
}

async function dispatch(
  body: Record<string, unknown>,
  provider: CoachProvider | null,
  log: Logger,
): Promise<QuestionsResult | FeedbackResult | WrapupResult | AskResult> {
  switch (body.action) {
    case "questions": {
      const input = parseQuestions(body);
      if (!provider) return mockQuestions(input.job, input.count);
      return normalizeQuestions(await provider.generate("questions", ROUTES.questions, questionsPrompt(input), log), input);
    }
    case "feedback": {
      const input = parseFeedback(body);
      if (wordCount(input.transcript) === 0) bad("There is no answer to review. Record or type an answer first.");
      if (!provider) return mockFeedback(input);
      return normalizeFeedback(await provider.generate("feedback", ROUTES.feedback, feedbackPrompt(input), log), input);
    }
    case "wrapup": {
      const input = parseWrapup(body);
      if (!provider) return mockWrapup(input);
      return normalizeWrapup(await provider.generate("wrapup", ROUTES.wrapup, wrapupPrompt(input), log), input);
    }
    case "ask": {
      const input = parseAsk(body);
      if (!provider) return mockAsk(input);
      return normalizeAsk(await provider.generate("ask", ROUTES.ask, askPrompt(input), log));
    }
    default:
      return bad(`"action" must be "questions", "feedback", "wrapup" or "ask".`);
  }
}

export interface HandlerOptions {
  client?: ClaudeClient | null;
  provider?: CoachProvider | null;
  /** Demo/test responses must be explicitly enabled, including in tests. */
  mock?: boolean;
  log?: Logger;
  /** When set, POST /coach needs this value in the x-coach-token header (16 characters or more). */
  token?: string;
  /** Overrides for the per-client and daily limits (see DEFAULT_LIMITS). */
  limits?: Partial<RateLimits>;
  /** A browser origin allowed to call the coach. None by default: the app is not a browser. */
  corsOrigin?: string;
  /** Take the client address from x-forwarded-for. Only behind a gateway that sets it (Supabase). */
  trustForwardedFor?: boolean;
  /** Clock for the rate limits, for tests. */
  now?: () => number;
}

/** What Deno.serve passes alongside the request; only the peer address is used. */
export type RequestInfo = { remoteAddr?: { hostname?: string } };

export function createHandler(opts: HandlerOptions): (req: Request, info?: RequestInfo) => Promise<Response> {
  const mock = opts.mock === true;
  const provider = mock ? null : opts.provider ?? (opts.client ? createClaudeProvider(opts.client) : null);
  const log: Logger = opts.log ?? ((entry) => console.log(JSON.stringify({ t: new Date().toISOString(), ...entry })));
  const expected = opts.token === undefined ? null : tokenDigest(opts.token);
  const limits = { ...DEFAULT_LIMITS, ...opts.limits };
  const perMinute = new Windows(MINUTE, limits.perMinute);
  const perDay = new Windows(DAY, limits.perDay);
  const everyone = new Windows(DAY, limits.globalPerDay);
  const badTokens = new Windows(10 * MINUTE, limits.badTokens);
  const now = opts.now ?? Date.now;
  const headers = { ...SECURITY_HEADERS, ...corsHeaders(opts.corsOrigin) };
  const trusted = async (req: Request) => !expected || await tokenMatches(req.headers.get(TOKEN_HEADER), await expected);

  return async (req: Request, info?: RequestInfo): Promise<Response> => {
    const started = Date.now();
    const path = routePath(new URL(req.url).pathname);
    let action = "-";
    let res: Response;
    try {
      if (req.method === "OPTIONS") {
        res = new Response(null, { status: 204, headers });
      } else if (path === "/health" || path === "/coach/health") {
        if (req.method !== "GET") throw new CoachError(405, "bad_request", "Use GET for health checks.");
        const configured = mock || provider !== null;
        // Anyone can see whether the coach is up (the phone's browser check); only the app sees what runs it.
        res = json(configured ? 200 : 503, await trusted(req)
          ? {
            ok: configured, mock,
            provider: mock ? "demo" : provider?.name ?? "unconfigured",
            model: provider?.model ?? null,
            cloud: provider?.cloud ?? false,
          }
          : { ok: configured, mock }, headers);
      } else if (path === "/" || path === "/coach") {
        if (req.method !== "POST") throw new CoachError(405, "bad_request", "Use POST with a JSON body.");
        const client = clientKey(req, info, opts.trustForwardedFor === true);
        const t = now();
        if (expected) {
          if (badTokens.full(client, t)) {
            throw new CoachError(429, "rate_limited", "Too many wrong access tokens. Wait ten minutes and try again.");
          }
          if (!await trusted(req)) {
            badTokens.hit(client, t);
            throw new CoachError(401, "unauthorized", "This app is not allowed to use the coach.");
          }
        }
        if (!isJson(req)) throw new CoachError(415, "bad_request", "Send the request as application/json.");
        if (!perMinute.hit(client, t)) {
          throw new CoachError(429, "rate_limited", "Too many requests. Wait a minute and try again.");
        }
        if (!perDay.hit(client, t)) {
          throw new CoachError(429, "rate_limited", "You have reached today's practice limit. Try again tomorrow.");
        }
        if (!everyone.hit("*", t)) {
          throw new CoachError(429, "rate_limited", "The coach has reached today's limit. Try again tomorrow.");
        }
        const body = await readJson(req);
        action = typeof body.action === "string" ? body.action.slice(0, 20) : "-";
        if (!mock && !provider) {
          throw new CoachError(503, "not_configured", "The AI coach is not configured. Start the coach server with Ollama or an Anthropic API key.");
        }
        res = json(200, { ...(await dispatch(body, provider, log)), mock }, headers);
      } else {
        throw new CoachError(404, "bad_request", `Nothing at ${path}. Use POST /coach or GET /health.`);
      }
    } catch (err) {
      const e = toCoachError(err, log);
      res = json(e.status, { error: { code: e.code, message: e.message } }, headers);
    }
    log({ event: "request", method: req.method, path, action, status: res.status, ms: Date.now() - started, mock });
    return res;
  };
}

// ---------------------------------------------------------------------------
// Entry point: `deno run` locally, or the Supabase Edge Runtime
// ---------------------------------------------------------------------------

function envInt(name: string): number | undefined {
  const raw = Deno.env.get(name)?.trim();
  if (!raw) return undefined;
  const n = Number(raw);
  if (!Number.isInteger(n) || n < 1) throw new Error(`${name} must be a whole number of 1 or more.`);
  return n;
}

function main(): void {
  const forceMock = Deno.env.get("COACH_MOCK") === "1";
  const hasCredential = Boolean(Deno.env.get("ANTHROPIC_API_KEY") || Deno.env.get("ANTHROPIC_AUTH_TOKEN"));
  const ollamaModel = Deno.env.get("OLLAMA_MODEL")?.trim();
  const ollamaUrl = Deno.env.get("OLLAMA_URL")?.trim() || undefined;
  const ollamaCloud = Deno.env.get("OLLAMA_CLOUD") === "1";
  // One retry and a 60 s per-attempt timeout: the user is waiting on a phone.
  const client = !forceMock && hasCredential ? new Anthropic({ timeout: 60_000, maxRetries: 1 }) : null;
  const provider = !forceMock && ollamaModel
    ? createOllamaProvider({ model: ollamaModel, baseUrl: ollamaUrl, cloud: ollamaCloud || undefined })
    : client
    ? createClaudeProvider(client)
    : null;
  // Without a token anyone who can reach the coach can spend its AI credit, so an open coach is
  // only allowed on this computer's loopback address, or when COACH_ALLOW_OPEN=1 says so.
  const token = Deno.env.get("COACH_TOKEN")?.trim() || undefined;
  const allowOpen = Deno.env.get("COACH_ALLOW_OPEN") === "1";
  const limits: Partial<RateLimits> = {};
  for (const [key, name] of [["perMinute", "COACH_RATE_PER_MINUTE"], ["perDay", "COACH_RATE_PER_DAY"], ["globalPerDay", "COACH_DAILY_LIMIT"]] as const) {
    const n = envInt(name);
    if (n !== undefined) limits[key] = n;
  }
  const corsOrigin = Deno.env.get("COACH_CORS_ORIGIN")?.trim() || undefined;
  const edge = "EdgeRuntime" in globalThis;
  const handler = createHandler({ provider, mock: forceMock, token, limits, corsOrigin, trustForwardedFor: edge });
  const mode = forceMock
    ? "mock"
    : provider
    ? `${provider.name}, ${provider.model}`
    : "unconfigured";
  const access = token ? "access token required" : "open";

  if (edge) {
    if (!token && !allowOpen) {
      throw new Error("Set the COACH_TOKEN secret (16 characters or more) before deploying the coach.");
    }
    console.log(`coach ready (${mode}, ${access})`);
    Deno.serve(handler);
    return;
  }
  const port = Number(Deno.env.get("PORT") ?? 8787);
  const hostname = Deno.env.get("HOST") ?? "127.0.0.1";
  if (!token && !allowOpen && !isLoopback(hostname)) {
    console.error(`Refusing to listen on ${hostname} without COACH_TOKEN: anyone on the network could use your AI credit.`);
    console.error("Start it with tools/coach/run-local.sh, which creates a token, or set HOST=127.0.0.1.");
    Deno.exit(1);
  }
  Deno.serve(
    { port, hostname, onListen: (a) => console.log(`coach listening on http://${a.hostname}:${a.port} (${mode}, ${access})`) },
    handler,
  );
}

if (import.meta.main || "EdgeRuntime" in globalThis) main();
