// Real-provider smoke test using only invented interview answers.
// Run: COACH_TOKEN=<token from supabase/functions/.env> deno run --allow-net --allow-env tools/coach/smoke.ts http://127.0.0.1:8787
// It deliberately fails for demo mode; no personal recordings are read.

const base = new URL(Deno.args[0] ?? "http://127.0.0.1:8787");
const job = "I am applying for a junior software developer job at a small company that builds appointment booking apps";
const transcripts = [
  "I want this job because I enjoy building useful software and I want to learn how a small team ships apps. At school I built a Python timetable tool, and I liked seeing classmates use it. Booking apps interest me because reliable scheduling saves people time.",
  "I would just try things until it works. We normally work hard as a team and can sort problems out. I do not really have a method for finding the cause of bugs.",
  "During a school project my teammate wanted to add more features and I wanted to fix the login bug first. I showed that users could not sign in and suggested finishing the fix before adding features. We agreed on that order and submitted a working app on time.",
  "For a school club I needed to learn how to read a spreadsheet with Python. I read a small example in the documentation, tried it on three test rows, then asked a classmate to check the output. The script saved our organiser an hour of copying names each week.",
  "When I make a mistake I first check who is affected and tell my teammate what happened. I would reproduce the problem with a small test, fix it, and check the original steps again before sharing the change. I would also add a test to catch the same mistake next time.",
];

function check(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function record(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

async function request(path: string, body?: Record<string, unknown>): Promise<Record<string, unknown>> {
  const started = performance.now();
  const response = await fetch(new URL(path, base), {
    method: body ? "POST" : "GET",
    headers: { "content-type": "application/json", "x-coach-token": Deno.env.get("COACH_TOKEN") ?? "" },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(90_000),
  });
  const value: unknown = await response.json();
  check(response.ok && record(value), `${body?.action ?? "health"} failed: HTTP ${response.status} ${JSON.stringify(value)}`);
  check(value.mock === false, "This is a demo coach. Start a real provider before running this smoke test.");
  console.log(`${body?.action ?? "health"}: HTTP ${response.status}, ${((performance.now() - started) / 1000).toFixed(1)}s, mock:false`);
  return value;
}

function metrics(transcript: string, duration: number) {
  const words = transcript.split(/\s+/).length;
  return {
    duration_s: duration, words, wpm: Math.round(words / duration * 60),
    pauses_over_1s: 2, longest_pause_s: 1.4,
    filler_count: 0, fillers: {}, loudness_db_mean: -23, loudness_db_sd: 3,
    trailing_off: false, pitch_hz_mean: 150, pitch_semitone_sd: 3,
    monotone: false, speech_ratio: 0.85,
  };
}

const health = await request("/health");
const questions = await request("/coach", { action: "questions", job, count: transcripts.length });
check(Array.isArray(questions.questions) && questions.questions.length === transcripts.length, "Expected five real questions.");
const answers: Record<string, unknown>[] = [];
for (let i = 0; i < transcripts.length; i++) {
  const question = questions.questions[i];
  check(record(question) && typeof question.text === "string", "Question text is missing.");
  const feedback = await request("/coach", {
    action: "feedback", job, question: question.text, transcript: transcripts[i],
    delivery: metrics(transcripts[i], i === 1 ? 9 : 24),
  });
  for (const key of ["headline", "problem", "fix", "strength", "delivery"]) {
    check(typeof feedback[key] === "string" && feedback[key], `Missing feedback.${key}`);
  }
  answers.push({ question: question.text, transcript: transcripts[i], ...feedback });
}
const wrapup = await request("/coach", { action: "wrapup", job, answers });
check(Array.isArray(wrapup.tips) && wrapup.tips.length >= 3, "Expected personal tips.");
check(Array.isArray(wrapup.last_minute_notes) && wrapup.last_minute_notes.length >= 3, "Expected interview reminders.");
check(Array.isArray(wrapup.stories_to_use) && wrapup.stories_to_use.every((s) => typeof s === "string"), "The app expects stories as strings.");
console.log(JSON.stringify({ health, questions, answers, wrapup }, null, 2));
