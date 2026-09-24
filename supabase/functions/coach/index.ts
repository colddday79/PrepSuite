// PrepSuite coach: the one HTTP service between the app and Claude.
//
// Runs unchanged locally (`deno run`, see tools/coach/run-local.sh) and as a
// Supabase Edge Function. Audio never reaches this service: the app sends the
// on-device transcript plus delivery numbers and gets short JSON back.
//
//   POST /coach   {"action": "questions" | "feedback" | "wrapup", ...}
//   GET  /health  {"ok": true, "mock": <bool>}
//
// Mock mode (deterministic, no Claude calls) when no Anthropic credential is
// set or COACH_MOCK=1.

import Anthropic from "npm:@anthropic-ai/sdk@0.128.0";
import { mockFeedback, mockQuestions, mockWrapup } from "./mock.ts";
import {
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
  feedbackText: 1000, // headline / problem / delivery echoed back in wrap-up answers
  bodyBytes: 200_000,
} as const;

// Server-side refusal fallbacks: if a safety classifier declines, the API
// re-runs the same request on Anthropic's recommended fallback model (chosen
// by refusal category) inside the same call.
const FALLBACK_BETA = "server-side-fallback-2026-07-01";
// The header the SDK's own beta structured-output helper (beta.messages.parse)
// sends. We call beta.messages.create directly so stop_reason is checked
// before the JSON is parsed.
const STRUCTURED_OUTPUTS_BETA = "structured-outputs-2025-12-15";

type Route = "questions" | "feedback" | "wrapup";

interface RouteSpec {
  system: string;
  schema: Record<string, unknown>;
  effort: "low" | "medium" | "high";
  maxTokens: number;
}

const ROUTES: Record<Route, RouteSpec> = {
  // low: a short, well-specified list right after the 10 s recording; the user is watching a spinner.
  questions: { system: QUESTIONS_SYSTEM, schema: QUESTIONS_SCHEMA, effort: "low", maxTokens: 16000 },
  // medium: the core judgement (one biggest problem, exact quote, number-grounded delivery) needs some thinking, but it runs after every answer.
  feedback: { system: FEEDBACK_SYSTEM, schema: FEEDBACK_SCHEMA, effort: "medium", maxTokens: 16000 },
  // medium: synthesis across up to 10 answers under a no-invented-facts rule; runs once per session.
  wrapup: { system: WRAPUP_SYSTEM, schema: WRAPUP_SCHEMA, effort: "medium", maxTokens: 16000 },
};

/** The slice of the Anthropic client this service uses (tests pass a fake). */
export interface ClaudeClient {
  beta: {
    messages: {
      create(params: Anthropic.Beta.MessageCreateParamsNonStreaming): PromiseLike<Anthropic.Beta.BetaMessage>;
    };
  };
}

export type Logger = (entry: Record<string, unknown>) => void;

type ErrorCode = "bad_request" | "upstream" | "rate_limited" | "not_configured";

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
    if (typeof count !== "number" || !Number.isFinite(count) || count < 0 || count > 10000) {
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

// ---------------------------------------------------------------------------
// Claude call
// ---------------------------------------------------------------------------

async function callClaude(client: ClaudeClient, route: Route, userContent: string, log: Logger): Promise<unknown> {
  const spec = ROUTES[route];
  const started = Date.now();
  const message = await client.beta.messages.create({
    model: MODEL,
    max_tokens: spec.maxTokens,
    thinking: { type: "adaptive" },
    output_config: { effort: spec.effort, format: { type: "json_schema", schema: spec.schema } },
    system: [{ type: "text", text: spec.system, cache_control: { type: "ephemeral" } }],
    messages: [{ role: "user", content: userContent }],
    betas: [FALLBACK_BETA, STRUCTURED_OUTPUTS_BETA],
    fallbacks: "default",
  });

  log({
    event: "claude",
    route,
    ms: Date.now() - started,
    served_by: message.model,
    fallback: (message.usage.iterations ?? []).some((it) => it.type === "fallback_message"),
    stop: message.stop_reason,
    input_tokens: message.usage.input_tokens,
    output_tokens: message.usage.output_tokens,
    cache_read_tokens: message.usage.cache_read_input_tokens ?? 0,
  });

  // Check stop_reason before reading content. A refusal here means the whole
  // fallback chain declined.
  if (message.stop_reason === "refusal") {
    throw new CoachError(502, "upstream", "The AI could not respond to this one. Try again with a different answer.");
  }
  if (message.stop_reason === "max_tokens") {
    throw new CoachError(502, "upstream", "The AI reply was cut off. Try again.");
  }

  // The served answer follows the last fallback marker (if a fallback happened).
  const start = message.content.findLastIndex((b) => b.type === "fallback") + 1;
  const json = message.content
    .slice(start)
    .map((b) => (b.type === "text" ? b.text : ""))
    .join("");
  try {
    return JSON.parse(json);
  } catch {
    badShape();
  }
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
  return parts.every((p) => haystack.includes(` ${p} `)) ? q : "";
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
  for (const q of raw.questions) if (isRecord(q)) add(clean(q.text), clean(q.focus, 8));
  if (!items.length) badShape();
  // The app expects exactly `count`; top up from the job-aware defaults in the rare case the model returns fewer.
  for (const q of mockQuestions(input.job, LIMITS.count.max).questions) {
    if (items.length >= input.count) break;
    add(q.text, q.focus);
  }
  return {
    job_title: clean(raw.job_title, 10) || mockQuestions(input.job, 1).job_title,
    questions: items.slice(0, input.count).map((q, i) => ({ id: `q${i + 1}`, ...q })),
  };
}

function normalizeFeedback(raw: unknown, input: FeedbackInput): FeedbackResult {
  if (!isRecord(raw)) badShape();
  const out: FeedbackResult = {
    headline: clean(raw.headline, 12),
    problem: clean(raw.problem),
    evidence: typeof raw.evidence === "string" ? verifiedQuote(raw.evidence, input.transcript) : "",
    fix: clean(raw.fix),
    delivery: clean(raw.delivery),
    strength: clean(raw.strength),
  };
  if (!out.headline || !out.problem || !out.fix) badShape();
  return out;
}

function list(v: unknown, max: number): string[] {
  return Array.isArray(v) ? v.map((s) => clean(s)).filter(Boolean).slice(0, max) : [];
}

function normalizeWrapup(raw: unknown): WrapupResult {
  if (!isRecord(raw)) badShape();
  const out: WrapupResult = {
    tips: list(raw.tips, 5),
    last_minute_notes: list(raw.last_minute_notes, 6),
    stories_to_use: list(raw.stories_to_use, 3),
  };
  if (!out.tips.length || !out.last_minute_notes.length) badShape();
  return out;
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
    detail: err instanceof Error ? err.message : String(err),
  });
  return e;
}

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------

const CORS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "GET, POST, OPTIONS",
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json; charset=utf-8" },
  });
}

/** "/functions/v1/coach/health/" -> "/coach/health"; "" -> "/". */
function routePath(pathname: string): string {
  const p = pathname.replace(/\/+$/, "").replace(/^\/functions\/v1(?=\/|$)/, "");
  return p || "/";
}

async function readJson(req: Request): Promise<Record<string, unknown>> {
  if (Number(req.headers.get("content-length") ?? 0) > LIMITS.bodyBytes) bad("Request body is too large.");
  const raw = await req.text();
  if (raw.length > LIMITS.bodyBytes) bad("Request body is too large.");
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
  client: ClaudeClient | null,
  log: Logger,
): Promise<QuestionsResult | FeedbackResult | WrapupResult> {
  switch (body.action) {
    case "questions": {
      const input = parseQuestions(body);
      if (!client) return mockQuestions(input.job, input.count);
      return normalizeQuestions(await callClaude(client, "questions", questionsPrompt(input), log), input);
    }
    case "feedback": {
      const input = parseFeedback(body);
      // Nothing was said at all: no need to ask the model to point that out.
      if (!client || wordCount(input.transcript) === 0) return mockFeedback(input);
      return normalizeFeedback(await callClaude(client, "feedback", feedbackPrompt(input), log), input);
    }
    case "wrapup": {
      const input = parseWrapup(body);
      if (!client) return mockWrapup(input);
      return normalizeWrapup(await callClaude(client, "wrapup", wrapupPrompt(input), log));
    }
    default:
      return bad(`"action" must be "questions", "feedback" or "wrapup".`);
  }
}

export interface HandlerOptions {
  /** Claude client, or null for mock mode. */
  client: ClaudeClient | null;
  log?: Logger;
}

export function createHandler(opts: HandlerOptions): (req: Request) => Promise<Response> {
  const { client } = opts;
  const log: Logger = opts.log ?? ((entry) => console.log(JSON.stringify({ t: new Date().toISOString(), ...entry })));
  const mock = client === null;

  return async (req: Request): Promise<Response> => {
    const started = Date.now();
    const path = routePath(new URL(req.url).pathname);
    let action = "-";
    let res: Response;
    try {
      if (req.method === "OPTIONS") {
        res = new Response(null, { status: 204, headers: CORS });
      } else if (path === "/health" || path === "/coach/health") {
        if (req.method !== "GET") throw new CoachError(405, "bad_request", "Use GET for health checks.");
        res = json(200, { ok: true, mock });
      } else if (path === "/" || path === "/coach") {
        if (req.method !== "POST") throw new CoachError(405, "bad_request", "Use POST with a JSON body.");
        const body = await readJson(req);
        action = typeof body.action === "string" ? body.action.slice(0, 20) : "-";
        res = json(200, { ...(await dispatch(body, client, log)), mock });
      } else {
        throw new CoachError(404, "bad_request", `Nothing at ${path}. Use POST /coach or GET /health.`);
      }
    } catch (err) {
      const e = toCoachError(err, log);
      res = json(e.status, { error: { code: e.code, message: e.message } });
    }
    log({ event: "request", method: req.method, path, action, status: res.status, ms: Date.now() - started, mock });
    return res;
  };
}

// ---------------------------------------------------------------------------
// Entry point: `deno run` locally, or the Supabase Edge Runtime
// ---------------------------------------------------------------------------

function main(): void {
  const forceMock = Deno.env.get("COACH_MOCK") === "1";
  const hasCredential = Boolean(Deno.env.get("ANTHROPIC_API_KEY") || Deno.env.get("ANTHROPIC_AUTH_TOKEN"));
  // One retry and a 60 s per-attempt timeout: the user is waiting on a phone.
  const client = !forceMock && hasCredential ? new Anthropic({ timeout: 60_000, maxRetries: 1 }) : null;
  const handler = createHandler({ client });
  const mode = client ? `live, ${MODEL}` : "mock";

  if ("EdgeRuntime" in globalThis) {
    console.log(`coach ready (${mode})`);
    Deno.serve(handler);
    return;
  }
  const port = Number(Deno.env.get("PORT") ?? 8787);
  const hostname = Deno.env.get("HOST") ?? "0.0.0.0";
  Deno.serve(
    { port, hostname, onListen: (a) => console.log(`coach listening on http://${a.hostname}:${a.port} (${mode})`) },
    handler,
  );
}

if (import.meta.main || "EdgeRuntime" in globalThis) main();
