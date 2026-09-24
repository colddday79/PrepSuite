import { CoachError, type CoachProvider, type RouteSpec } from "./index.ts";

interface OllamaOptions {
  model: string;
  baseUrl?: string;
  cloud?: boolean;
  timeoutMs?: number;
  fetcher?: typeof fetch;
}

const REPLY_BYTES = 64_000;

async function limitedJson(response: Response): Promise<unknown> {
  if (!response.body) throw new CoachError(502, "upstream", "The AI returned an empty reply. Try again.");
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let bytes = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > REPLY_BYTES) {
        await reader.cancel();
        throw new CoachError(502, "upstream", "The AI reply was too long. Try again.");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const all = new Uint8Array(bytes);
  let offset = 0;
  for (const chunk of chunks) {
    all.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    return JSON.parse(new TextDecoder().decode(all));
  } catch {
    throw new CoachError(502, "upstream", "The AI reply could not be read. Try again.");
  }
}

/** Only a whole JSON response or a single fenced JSON block is accepted. */
export function parseOllamaJson(content: string): unknown {
  const raw = content.trim();
  const fenced = /^```(?:json)?\s*\n([\s\S]*?)\n```\s*$/i.exec(raw);
  try {
    return JSON.parse(fenced ? fenced[1] : raw);
  } catch {
    throw new CoachError(502, "upstream", "The AI reply could not be read. Try again.");
  }
}

function record(v: unknown): v is Record<string, unknown> {
  return v !== null && typeof v === "object" && !Array.isArray(v);
}

function messages(spec: RouteSpec, prompt: string) {
  return [
    {
      role: "system",
      content: `${spec.system}\n\nReturn one JSON object only. No markdown or commentary. It must match this JSON schema exactly:\n${JSON.stringify(spec.schema)}`,
    },
    { role: "user", content: prompt },
  ];
}

/** The locally installed Ollama app manages its own cloud sign-in. No keys go to Flutter. */
export function createOllamaProvider(options: OllamaOptions): CoachProvider {
  const base = new URL(options.baseUrl ?? "http://127.0.0.1:11434");
  if (!["http:", "https:"].includes(base.protocol) || base.username || base.password) {
    throw new Error("OLLAMA_URL must be an http(s) URL without embedded credentials.");
  }
  const cloud = options.cloud ?? /(?:-cloud|:cloud)$/.test(options.model);
  const fetcher = options.fetcher ?? fetch;
  return {
    name: "ollama", model: options.model, cloud,
    async generate(route, spec, prompt, log) {
      const started = Date.now();
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), options.timeoutMs ?? 45_000);
      try {
        const response = await fetcher(new URL("/api/chat", base), {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({
            model: options.model,
            messages: messages(spec, prompt),
            stream: false,
            think: false,
            // Cloud ignores schema enforcement; its returned JSON is validated by the coach.
            ...(cloud ? {} : { format: spec.schema }),
            options: { temperature: 0.2, num_predict: spec.maxTokens },
          }),
          signal: controller.signal,
        });
        if (!response.ok) {
          await response.body?.cancel();
          if (response.status === 401 || response.status === 403) {
            throw new CoachError(503, "not_configured", "Sign in to Ollama on the coach computer, then try again.");
          }
          if (response.status === 404) {
            throw new CoachError(503, "not_configured", "The selected AI model is not available in Ollama.");
          }
          if (response.status === 429) {
            throw new CoachError(429, "rate_limited", "The AI usage limit was reached. Wait and try again.");
          }
          throw new CoachError(502, "upstream", "The AI service returned an error. Try again.");
        }
        const reply = await limitedJson(response);
        if (!record(reply) || !record(reply.message) || typeof reply.message.content !== "string" || reply.done !== true) {
          throw new CoachError(502, "upstream", "The AI reply was incomplete. Try again.");
        }
        if (reply.done_reason && reply.done_reason !== "stop") {
          throw new CoachError(502, "upstream", "The AI reply was cut off. Try again.");
        }
        const result = parseOllamaJson(reply.message.content);
        log({ event: "ai", provider: "ollama", route, model: options.model, ms: Date.now() - started });
        return result;
      } catch (err) {
        if (err instanceof CoachError) throw err;
        if (controller.signal.aborted) {
          throw new CoachError(504, "upstream", "The AI took too long to answer. Try again.");
        }
        throw new CoachError(502, "upstream", "Could not reach Ollama. Keep the coach computer awake with Ollama running.");
      } finally {
        clearTimeout(timer);
      }
    },
  };
}
