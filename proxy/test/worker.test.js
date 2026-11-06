import assert from "node:assert/strict";
import { test, beforeEach } from "node:test";
import { handle, deviceToken, MAX_BODY_BYTES } from "../src/worker.js";

const TOKEN = "a".repeat(40);
const NOW = new Date("2026-11-05T12:00:00Z");

function kv() {
  const store = new Map();
  return {
    store,
    async get(key) { return store.get(key) ?? null; },
    async put(key, value) { store.set(key, value); },
  };
}

let env;
let upstreamCalls;

beforeEach(() => {
  env = { OPENAI_API_KEY: "sk-real", LIMITS: kv(), DAILY_LIMIT: "3", GLOBAL_DAILY_LIMIT: "100" };
  upstreamCalls = [];
  globalThis.fetch = async (url, init) => {
    upstreamCalls.push({ url, init });
    return new Response(JSON.stringify({ answers: [] }), { status: 200, headers: { "content-type": "application/json" } });
  };
});

function post(path, body = { model: "gpt-6-luna" }, headers = {}) {
  return new Request(`https://proxy.example${path}`, {
    method: "POST",
    headers: { authorization: `Bearer ${TOKEN}`, "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

test("forwards a decisions request with the real key, not the device token", async () => {
  const response = await handle(post("/v1/decisions"), env, NOW);
  assert.equal(response.status, 200);
  assert.equal(upstreamCalls.length, 1);
  assert.equal(upstreamCalls[0].url, "https://api.openai.com/v1/decisions");
  assert.equal(upstreamCalls[0].init.headers.authorization, "Bearer sk-real");
});

test("only the two endpoints are open", async () => {
  assert.equal((await handle(post("/v1/chat/completions"), env, NOW)).status, 404);
  assert.equal((await handle(post("/v1/files"), env, NOW)).status, 404);
  assert.equal(upstreamCalls.length, 0);
});

test("GET is refused, health is open", async () => {
  const get = new Request("https://proxy.example/v1/decisions", { method: "GET" });
  assert.equal((await handle(get, env, NOW)).status, 405);
  const health = new Request("https://proxy.example/health");
  assert.equal((await handle(health, env, NOW)).status, 200);
});

test("needs a well-formed device token", async () => {
  const request = new Request("https://proxy.example/v1/decisions", {
    method: "POST", headers: { authorization: "Bearer short" }, body: "{}",
  });
  assert.equal((await handle(request, env, NOW)).status, 401);
  assert.equal(deviceToken(new Request("https://x", { headers: { authorization: `Bearer ${TOKEN}` } })), TOKEN);
  assert.equal(deviceToken(new Request("https://x")), null);
});

test("checks the app secret when one is set", async () => {
  env.APP_SECRET = "s3cret";
  assert.equal((await handle(post("/v1/decisions"), env, NOW)).status, 401);
  assert.equal((await handle(post("/v1/decisions", undefined, { "x-wakeup-app": "s3cret" }), env, NOW)).status, 200);
});

test("only allowed models", async () => {
  assert.equal((await handle(post("/v1/decisions", { model: "gpt-9-huge" }), env, NOW)).status, 400);
  assert.equal((await handle(post("/v1/decisions", { model: "gpt-6.1-terra" }), env, NOW)).status, 400);
  assert.equal((await handle(post("/v1/responses", { model: "gpt-6.1-terra" }), env, NOW)).status, 200);
});

test("rejects bad JSON and streaming", async () => {
  const bad = new Request("https://proxy.example/v1/decisions", {
    method: "POST", headers: { authorization: `Bearer ${TOKEN}` }, body: "not json",
  });
  assert.equal((await handle(bad, env, NOW)).status, 400);
  assert.equal((await handle(post("/v1/responses", { model: "gpt-6-luna", stream: true }), env, NOW)).status, 400);
});

test("rejects oversized requests", async () => {
  const big = new Request("https://proxy.example/v1/decisions", {
    method: "POST",
    headers: { authorization: `Bearer ${TOKEN}`, "content-length": String(MAX_BODY_BYTES + 1) },
    body: "{}",
  });
  assert.equal((await handle(big, env, NOW)).status, 413);
});

test("a device is limited per day, then resets tomorrow", async () => {
  for (let i = 0; i < 3; i++) assert.equal((await handle(post("/v1/decisions"), env, NOW)).status, 200);
  const blocked = await handle(post("/v1/decisions"), env, NOW);
  assert.equal(blocked.status, 429);
  assert.ok(blocked.headers.get("retry-after"));
  assert.equal(upstreamCalls.length, 3);

  const tomorrow = new Date("2026-11-06T12:00:00Z");
  assert.equal((await handle(post("/v1/decisions"), env, tomorrow)).status, 200);
});

test("another device is not affected", async () => {
  for (let i = 0; i < 3; i++) await handle(post("/v1/decisions"), env, NOW);
  const other = new Request("https://proxy.example/v1/decisions", {
    method: "POST", headers: { authorization: `Bearer ${"b".repeat(40)}` }, body: JSON.stringify({ model: "gpt-6-luna" }),
  });
  assert.equal((await handle(other, env, NOW)).status, 200);
});

test("the global cap stops everyone", async () => {
  env.GLOBAL_DAILY_LIMIT = "2";
  await handle(post("/v1/decisions"), env, NOW);
  await handle(post("/v1/decisions"), env, NOW);
  assert.equal((await handle(post("/v1/decisions"), env, NOW)).status, 429);
});

test("the device token is never stored in plain text", async () => {
  await handle(post("/v1/decisions"), env, NOW);
  for (const key of env.LIMITS.store.keys()) assert.ok(!key.includes(TOKEN));
});

test("an upstream 401 is shown as a proxy problem, other errors pass through", async () => {
  globalThis.fetch = async () => new Response(JSON.stringify({ error: { message: "bad key" } }), { status: 401 });
  assert.equal((await handle(post("/v1/decisions"), env, NOW)).status, 502);
  globalThis.fetch = async () => new Response(JSON.stringify({ error: { message: "slow down" } }), { status: 429 });
  assert.equal((await handle(post("/v1/decisions"), env, NOW)).status, 429);
});
