// Run with `npm test` (node:test; scripts/ts-loader.mjs transpiles the .ts).
import { test, afterEach } from "node:test";
import assert from "node:assert/strict";

import { sendCode, verifyCode } from "./api.ts";

const realFetch = globalThis.fetch;
afterEach(() => {
  globalThis.fetch = realFetch;
});

function respondWith(status, body) {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url, init });
    return new Response(body === undefined ? "not json" : JSON.stringify(body), { status });
  };
  return calls;
}

test("sendCode posts the phone and returns the body on success", async () => {
  const calls = respondWith(200, { success: true, expires_in_seconds: 300 });

  const result = await sendCode("+254712345678");

  assert.deepEqual(result, { ok: true, data: { success: true, expires_in_seconds: 300 } });
  assert.equal(calls[0].url, "http://localhost:4000/api/send-code");
  assert.equal(calls[0].init.method, "POST");
  assert.deepEqual(JSON.parse(calls[0].init.body), { phone: "+254712345678" });
});

test("API errors are passed through", async () => {
  respondWith(429, {
    success: false,
    error: "daily_limit_reached",
    message: "The daily SMS limit has been reached. Try again later.",
  });

  const result = await sendCode("+254712345678");

  assert.equal(result.ok, false);
  assert.equal(result.error.error, "daily_limit_reached");
});

test("non-JSON responses become http_error", async () => {
  respondWith(502);

  const result = await verifyCode("+254712345678", "123456");

  assert.equal(result.ok, false);
  assert.equal(result.error.error, "http_error");
  assert.match(result.error.message, /HTTP 502/);
});

test("network failures become network_error", async () => {
  globalThis.fetch = async () => {
    throw new TypeError("fetch failed");
  };

  const result = await verifyCode("+254712345678", "123456");

  assert.equal(result.ok, false);
  assert.equal(result.error.error, "network_error");
});
