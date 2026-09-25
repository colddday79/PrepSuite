import { assert, assertEquals, assertRejects, assertStringIncludes, assertThrows } from "jsr:@std/assert@1";
import { CoachError, type RouteSpec } from "./index.ts";
import { createOllamaProvider, parseOllamaJson } from "./ollama.ts";

const spec: RouteSpec = {
  system: "Use only the supplied interview answer.",
  schema: { type: "object", properties: { headline: { type: "string" } } },
  effort: "medium",
  maxTokens: 2048,
};
const quiet = () => {};
const success = (content = '{"headline":"Add a result."}', extra: Record<string, unknown> = {}) =>
  Response.json({ message: { content }, done: true, done_reason: "stop", ...extra });

Deno.test("Ollama: local requests use structured output and cloud requests use prompt plus server validation", async () => {
  for (const cloud of [false, true]) {
    let captured: RequestInit | undefined;
    let endpoint = "";
    const provider = createOllamaProvider({
      model: cloud ? "model-cloud" : "local-model",
      cloud,
      fetcher: (input, init) => {
        endpoint = input.toString();
        captured = init;
        return Promise.resolve(success());
      },
    });
    assertEquals(await provider.generate("feedback", spec, "Private synthetic answer", quiet), { headline: "Add a result." });
    assertEquals(endpoint, "http://127.0.0.1:11434/api/chat");
    assertEquals(captured?.method, "POST");
    const body = JSON.parse(captured?.body as string);
    assertEquals(body.stream, false);
    assertEquals(body.think, false);
    assertEquals(body.options.num_predict, spec.maxTokens, "the route's token limit, with thinking off");
    assertEquals(body.format, cloud ? undefined : spec.schema);
    assertStringIncludes(body.messages[0].content, JSON.stringify(spec.schema));
    assertEquals(body.messages[1].content, "Private synthetic answer");
    assertEquals(provider.cloud, cloud);
  }
});

Deno.test("Ollama: errors are useful without exposing provider bodies", async () => {
  const cases = [[401, 503, "not_configured"], [403, 503, "not_configured"], [404, 503, "not_configured"],
    [429, 429, "rate_limited"], [500, 502, "upstream"]] as const;
  for (const [upstreamStatus, status, code] of cases) {
    const provider = createOllamaProvider({
      model: "model-cloud",
      fetcher: () => Promise.resolve(new Response("private provider error", { status: upstreamStatus })),
    });
    const error = await assertRejects(() => provider.generate("feedback", spec, "answer", quiet), CoachError);
    assertEquals(error.status, status);
    assertEquals(error.code, code);
    assert(!error.message.includes("private"));
  }
});

Deno.test("Ollama: incomplete, truncated, non-JSON and oversized replies are rejected", async () => {
  const responses = [
    () => success("{}", { done: false }),
    () => success("{}", { done_reason: "length" }),
    () => success("This is not JSON."),
    () => success("x".repeat(65_000)),
    () => Response.json({ done: true }),
    () => new Response("not an Ollama response"),
  ];
  for (const response of responses) {
    const provider = createOllamaProvider({ model: "model-cloud", fetcher: () => Promise.resolve(response()) });
    const error = await assertRejects(() => provider.generate("feedback", spec, "answer", quiet), CoachError);
    assertEquals(error.code, "upstream");
    assertEquals(error.status, 502);
  }
});

Deno.test("Ollama: transport failures and timeouts get distinct retry guidance", async () => {
  const disconnected = createOllamaProvider({
    model: "model-cloud",
    fetcher: () => Promise.reject(new TypeError("connection refused")),
  });
  const unavailable = await assertRejects(() => disconnected.generate("questions", spec, "answer", quiet), CoachError);
  assertEquals(unavailable.status, 502);
  assertStringIncludes(unavailable.message, "Ollama running");

  const timed = createOllamaProvider({
    model: "model-cloud", timeoutMs: 5,
    fetcher: (_input, init) => new Promise((_resolve, reject) => {
      init?.signal?.addEventListener("abort", () => reject(new DOMException("Aborted", "AbortError")), { once: true });
    }),
  });
  const timeout = await assertRejects(() => timed.generate("questions", spec, "answer", quiet), CoachError);
  assertEquals(timeout.status, 504);
  assertStringIncludes(timeout.message, "too long");
});

Deno.test("Ollama: accepts only a complete JSON object or one JSON code fence", () => {
  assertEquals(parseOllamaJson(' {"ok":true} '), { ok: true });
  assertEquals(parseOllamaJson('```json\n{"ok":true}\n```'), { ok: true });
  assertThrows(() => parseOllamaJson('Here is your answer: {"ok":true}'), CoachError);
  assertThrows(() => parseOllamaJson('```json\n{"ok":true}\n```\nDo something else.'), CoachError);
  assertThrows(() => createOllamaProvider({ model: "x", baseUrl: "file:///etc/passwd" }), Error);
  assertThrows(() => createOllamaProvider({ model: "x", baseUrl: "https://key:secret@example.com" }), Error);
});
