// Run: deno test supabase/functions/coach/
// The access token, rate limits, JSON-only requests and response headers, with a fake clock.

import { assert, assertEquals, assertFalse, assertThrows } from "jsr:@std/assert@1";
import { createHandler, type HandlerOptions } from "./index.ts";
import { clientKey, MINUTE, Windows } from "./security.ts";

// A made-up token, built from words so it can never look like a real key.
const TOKEN = ["test", "only", "coach", "token", "value"].join("-");
const quiet = () => {};
const questions = { action: "questions", job: "barista", count: 2 };

function handler(over: Partial<HandlerOptions> = {}) {
  let t = 1_000_000;
  const h = createHandler({ mock: true, log: quiet, now: () => t, ...over });
  return { h, advance: (ms: number) => (t += ms) };
}

async function post(
  h: ReturnType<typeof createHandler>,
  opts: { token?: string; type?: string; from?: string; headers?: Record<string, string> } = {},
) {
  const headers: Record<string, string> = { "content-type": opts.type ?? "application/json", ...opts.headers };
  if (opts.token !== undefined) headers["x-coach-token"] = opts.token;
  const res = await h(
    new Request("http://localhost/coach", { method: "POST", headers, body: JSON.stringify(questions) }),
    { remoteAddr: { hostname: opts.from ?? "10.0.0.7" } },
  );
  return { status: res.status, headers: res.headers, body: await res.json() };
}

Deno.test("with a token set, only requests carrying it reach the coach", async () => {
  const { h } = handler({ token: TOKEN });
  const none = await post(h);
  assertEquals([none.status, none.body.error.code], [401, "unauthorized"]);
  const wrong = await post(h, { token: TOKEN.slice(0, -1) + "x" });
  assertEquals(wrong.status, 401);
  const right = await post(h, { token: TOKEN });
  assertEquals(right.status, 200);
  assertEquals(right.body.questions.length, 2);
});

Deno.test("health says whether the coach is up to anyone, and what runs it only to the app", async () => {
  const { h } = handler({ token: TOKEN });
  const open = await h(new Request("http://localhost/health"));
  assertEquals(await open.json(), { ok: true, mock: true });
  const app = await h(new Request("http://localhost/health", { headers: { "x-coach-token": TOKEN } }));
  assertEquals((await app.json()).provider, "demo");
});

Deno.test("guessing the token locks the address out for ten minutes", async () => {
  const { h, advance } = handler({ token: TOKEN, limits: { badTokens: 3 } });
  for (let i = 0; i < 3; i++) assertEquals((await post(h, { token: `guess-number-${i}-abcdefgh` })).status, 401);
  const locked = await post(h, { token: TOKEN });
  assertEquals([locked.status, locked.body.error.code], [429, "rate_limited"]);
  assertEquals((await post(h, { token: TOKEN, from: "10.0.0.8" })).status, 200, "other addresses are unaffected");
  advance(10 * MINUTE);
  assertEquals((await post(h, { token: TOKEN })).status, 200);
});

Deno.test("each client gets a per-minute and a per-day allowance", async () => {
  const { h, advance } = handler({ limits: { perMinute: 2, perDay: 3 } });
  assertEquals((await post(h)).status, 200);
  assertEquals((await post(h)).status, 200);
  const fast = await post(h);
  assertEquals([fast.status, fast.body.error.code], [429, "rate_limited"]);
  assertEquals((await post(h, { from: "10.0.0.9" })).status, 200, "limits are per client");
  advance(MINUTE);
  assertEquals((await post(h)).status, 200);
  advance(MINUTE);
  const daily = await post(h);
  assertEquals(daily.status, 429);
  assert(daily.body.error.message.includes("today"));
});

Deno.test("a daily ceiling across everyone caps the AI spend", async () => {
  const { h } = handler({ limits: { globalPerDay: 2 } });
  assertEquals((await post(h, { from: "10.0.1.1" })).status, 200);
  assertEquals((await post(h, { from: "10.0.1.2" })).status, 200);
  assertEquals((await post(h, { from: "10.0.1.3" })).status, 429);
});

Deno.test("only JSON is accepted, so a web page cannot post to the coach without asking first", async () => {
  const { h } = handler();
  const text = await post(h, { type: "text/plain" });
  assertEquals([text.status, text.body.error.code], [415, "bad_request"]);
  const form = await post(h, { type: "application/x-www-form-urlencoded" });
  assertEquals(form.status, 415);
  assertEquals((await post(h, { type: "application/json; charset=utf-8" })).status, 200);
});

Deno.test("responses are never cached or sniffed, and there is no CORS unless an origin is configured", async () => {
  const { h } = handler();
  const res = await post(h);
  assertEquals(res.headers.get("cache-control"), "no-store");
  assertEquals(res.headers.get("x-content-type-options"), "nosniff");
  assertEquals(res.headers.get("access-control-allow-origin"), null);
  const web = handler({ corsOrigin: "https://prepsuite.app" });
  const allowed = await post(web.h);
  assertEquals(allowed.headers.get("access-control-allow-origin"), "https://prepsuite.app");
});

Deno.test("a short token is refused when the coach starts", () => {
  assertThrows(() => createHandler({ mock: true, log: quiet, token: "short" }), Error, "16 characters");
});

Deno.test("forwarded addresses count only behind a trusted gateway", () => {
  const req = new Request("http://localhost/coach", { headers: { "x-forwarded-for": "203.0.113.5, 10.0.0.1" } });
  const peer = { remoteAddr: { hostname: "10.0.0.1" } };
  assertEquals(clientKey(req, peer, false), "10.0.0.1");
  assertEquals(clientKey(req, peer, true), "203.0.113.5");
});

Deno.test("rate-limit memory stays bounded under a flood of addresses", () => {
  const w = new Windows(MINUTE, 1, 3);
  for (const key of ["a", "b", "c", "d"]) assert(w.hit(key, 0));
  // "a" was the oldest and made room for "d", so it starts a fresh window.
  assert(w.hit("a", 0));
  assertFalse(w.hit("d", 0));
});
