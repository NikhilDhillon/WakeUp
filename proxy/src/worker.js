// WakeUp proxy: a small Cloudflare Worker that holds the OpenAI key and
// forwards the app's photo checks, so people using the app don't need their
// own key. It only forwards the two endpoints the app uses, caps the size of
// a request, and rate-limits each device.
//
// Secrets and settings (see README.md):
//   OPENAI_API_KEY   the key (wrangler secret put OPENAI_API_KEY)
//   APP_SECRET       optional shared value the app sends as X-WakeUp-App
//   DAILY_LIMIT      checks per device per day (default 40)
//   GLOBAL_DAILY_LIMIT  checks across everyone per day (default 2000)
//   LIMITS           a KV namespace that holds the counters

export const ALLOWED_PATHS = {
  "/v1/decisions": ["gpt-6-luna"],
  "/v1/responses": ["gpt-6-luna", "gpt-6.1-terra"],
};

export const MAX_BODY_BYTES = 8 * 1024 * 1024;
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{32,128}$/;

function json(status, body, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...headers },
  });
}

function error(status, message, headers) {
  return json(status, { error: { message } }, headers);
}

export function today(now = new Date()) {
  return now.toISOString().slice(0, 10);
}

// Bearer token the app made up for this install. It is not a secret from the
// device's owner; it only lets the proxy count requests per install.
export function deviceToken(request) {
  const header = request.headers.get("authorization") || "";
  const match = header.match(/^Bearer (.+)$/);
  return match && TOKEN_PATTERN.test(match[1]) ? match[1] : null;
}

async function sha256(text) {
  const bytes = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// KV is not atomic, so under heavy parallel use a device can slip a few
// requests past the limit. That is fine for a soft cap; the global cap and
// OpenAI's own spend limit are the hard stops.
async function bump(kv, key, limit) {
  const used = parseInt((await kv.get(key)) || "0", 10);
  if (used >= limit) return { allowed: false, used };
  await kv.put(key, String(used + 1), { expirationTtl: 60 * 60 * 36 });
  return { allowed: true, used: used + 1 };
}

export async function handle(request, env, now = new Date()) {
  const url = new URL(request.url);

  if (url.pathname === "/health") return json(200, { ok: true });

  if (request.method !== "POST") return error(405, "Use POST.");
  const allowedModels = ALLOWED_PATHS[url.pathname];
  if (!allowedModels) return error(404, "Not found.");

  if (env.APP_SECRET && request.headers.get("x-wakeup-app") !== env.APP_SECRET) {
    return error(401, "Unknown app.");
  }

  const token = deviceToken(request);
  if (!token) return error(401, "Missing or malformed device token.");

  const length = parseInt(request.headers.get("content-length") || "0", 10);
  if (length > MAX_BODY_BYTES) return error(413, "Request too large.");
  const text = await request.text();
  if (text.length > MAX_BODY_BYTES) return error(413, "Request too large.");

  let body;
  try {
    body = JSON.parse(text);
  } catch {
    return error(400, "Body must be JSON.");
  }
  if (!allowedModels.includes(body.model)) return error(400, "Model not allowed.");
  if (body.stream) return error(400, "Streaming is not supported.");

  const day = today(now);
  const deviceLimit = parseInt(env.DAILY_LIMIT || "40", 10);
  const globalLimit = parseInt(env.GLOBAL_DAILY_LIMIT || "2000", 10);
  const deviceKey = `d:${day}:${await sha256(token)}`;
  const globalKey = `g:${day}`;

  const global = await bump(env.LIMITS, globalKey, globalLimit);
  if (!global.allowed) return error(429, "The service is busy today. Try again tomorrow.", { "retry-after": "3600" });
  const device = await bump(env.LIMITS, deviceKey, deviceLimit);
  if (!device.allowed) return error(429, `Daily limit of ${deviceLimit} checks reached.`, { "retry-after": "3600" });

  const upstream = await fetch(`https://api.openai.com${url.pathname}`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${env.OPENAI_API_KEY}`,
      "content-type": "application/json",
    },
    body: text,
  });

  // Pass the answer (or OpenAI's error) straight back. OpenAI's 401 means the
  // proxy's own key is wrong, which must not look like the user's mistake.
  const status = upstream.status === 401 ? 502 : upstream.status;
  return new Response(upstream.body, {
    status,
    headers: { "content-type": upstream.headers.get("content-type") || "application/json" },
  });
}

export default {
  fetch(request, env) {
    return handle(request, env);
  },
};
