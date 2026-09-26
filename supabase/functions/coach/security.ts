// Access control for the coach: an access token, per-client rate limits, a daily ceiling and
// response headers. All of it runs before a request body is read or an AI provider is called.

/** How many requests the coach accepts. Counted in memory, per server instance. */
export interface RateLimits {
  /** Requests from one client in a minute. */
  perMinute: number;
  /** Requests from one client in a day. */
  perDay: number;
  /** Requests from everyone in a day: a ceiling on AI spend even if the token leaks. */
  globalPerDay: number;
  /** Wrong tokens from one client before it is turned away for ten minutes. */
  badTokens: number;
}

export const DEFAULT_LIMITS: RateLimits = { perMinute: 20, perDay: 300, globalPerDay: 2000, badTokens: 10 };

/** A shared secret shorter than this is too easy to guess. */
export const MIN_TOKEN_LENGTH = 16;

/** The header the app sends its access token in. Authorization stays free for a gateway's own auth. */
export const TOKEN_HEADER = "x-coach-token";

export const MINUTE = 60_000;
export const DAY = 24 * 60 * MINUTE;

/** Fixed-window counters, bounded in size so a flood of addresses cannot use up memory. */
export class Windows {
  private readonly counts = new Map<string, { start: number; count: number }>();

  constructor(private readonly size: number, private readonly max: number, private readonly cap = 10_000) {}

  /** Counts one hit for [key]; false once the key is over its limit in the current window. */
  hit(key: string, now: number): boolean {
    let window = this.current(key, now);
    if (!window) {
      // At capacity the oldest entry makes room (a Map iterates in insertion order).
      if (this.counts.size >= this.cap) this.counts.delete(this.counts.keys().next().value!);
      window = { start: now, count: 0 };
      this.counts.set(key, window);
    }
    window.count++;
    return window.count <= this.max;
  }

  /** Whether [key] has used up its limit in the current window, without counting a hit. */
  full(key: string, now: number): boolean {
    const window = this.current(key, now);
    return window !== undefined && window.count >= this.max;
  }

  private current(key: string, now: number) {
    const window = this.counts.get(key);
    if (window && now - window.start >= this.size) {
      this.counts.delete(key);
      return undefined;
    }
    return window;
  }
}

async function sha256(text: string): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
}

/** The expected token's digest, computed once. */
export function tokenDigest(token: string): Promise<Uint8Array> {
  if (token.length < MIN_TOKEN_LENGTH) {
    throw new Error(`The coach access token must be at least ${MIN_TOKEN_LENGTH} characters.`);
  }
  return sha256(token);
}

/** Compares digests in constant time, so response timing says nothing about the token. */
export async function tokenMatches(given: string | null, expected: Uint8Array): Promise<boolean> {
  if (!given) return false;
  const digest = await sha256(given);
  let diff = 0;
  for (let i = 0; i < expected.length; i++) diff |= digest[i] ^ expected[i];
  return diff === 0;
}

/** Who is asking: the peer address, or the first forwarded address behind a trusted gateway. */
export function clientKey(
  req: Request,
  info: { remoteAddr?: { hostname?: string } } | undefined,
  trustForwardedFor: boolean,
): string {
  if (trustForwardedFor) {
    const first = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
    if (first) return first;
  }
  return info?.remoteAddr?.hostname ?? "unknown";
}

/** Only JSON is accepted. Browsers can send text/plain across sites without asking first; this can't be. */
export function isJson(req: Request): boolean {
  return req.headers.get("content-type")?.split(";")[0].trim().toLowerCase() === "application/json";
}

/** On every response: nothing is cached (answers are personal), sniffed, framed or referred. */
export const SECURITY_HEADERS: Readonly<Record<string, string>> = {
  "cache-control": "no-store",
  "x-content-type-options": "nosniff",
  "content-security-policy": "default-src 'none'; frame-ancestors 'none'",
  "referrer-policy": "no-referrer",
};

/** CORS only for an origin that was configured. The app is not a browser, so by default there is none. */
export function corsHeaders(origin: string | undefined): Record<string, string> {
  if (!origin) return {};
  return {
    "access-control-allow-origin": origin,
    "access-control-allow-headers": `content-type, ${TOKEN_HEADER}`,
    "access-control-allow-methods": "GET, POST, OPTIONS",
    "vary": "origin",
  };
}

export function isLoopback(hostname: string): boolean {
  return ["127.0.0.1", "localhost", "::1"].includes(hostname);
}
