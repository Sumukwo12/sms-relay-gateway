"use client";

import Link from "next/link";
import { useState } from "react";
import { FileJson } from "lucide-react";
import { API_URL } from "../../lib/api";
import { Card, CodeBlock, PageHeader } from "../../components/ui";

type Lang = "curl" | "php" | "node" | "python";
const LANGS: { key: Lang; label: string }[] = [
  { key: "curl", label: "curl" },
  { key: "php", label: "PHP" },
  { key: "node", label: "Node.js" },
  { key: "python", label: "Python" },
];

function examples(base: string, key: string): Record<string, Record<Lang, string>> {
  return {
    otpSend: {
      curl: `curl -X POST ${base}/v1/otp/send \\
  -H "Authorization: Bearer ${key}" \\
  -H "Content-Type: application/json" \\
  -d '{"phone": "0712345678"}'

# 202 {"success": true, "expires_in_seconds": 300, "message": {"id": "msg_…", "status": "queued", …}}`,
      php: `<?php
$ch = curl_init("${base}/v1/otp/send");
curl_setopt_array($ch, [
    CURLOPT_POST => true,
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_HTTPHEADER => [
        "Authorization: Bearer ${key}",
        "Content-Type: application/json",
    ],
    CURLOPT_POSTFIELDS => json_encode(["phone" => "0712345678"]),
]);
$result = json_decode(curl_exec($ch), true);
$status = curl_getinfo($ch, CURLINFO_HTTP_CODE);  // 202 when queued`,
      node: `const res = await fetch("${base}/v1/otp/send", {
  method: "POST",
  headers: {
    Authorization: "Bearer ${key}",
    "Content-Type": "application/json",
  },
  body: JSON.stringify({ phone: "0712345678" }),
});
const result = await res.json(); // res.status === 202 when queued`,
      python: `import requests

res = requests.post(
    "${base}/v1/otp/send",
    headers={"Authorization": "Bearer ${key}"},
    json={"phone": "0712345678"},
)
result = res.json()  # res.status_code == 202 when queued`,
    },
    otpVerify: {
      curl: `curl -X POST ${base}/v1/otp/verify \\
  -H "Authorization: Bearer ${key}" \\
  -H "Content-Type: application/json" \\
  -d '{"phone": "0712345678", "code": "483921"}'

# 200 {"success": true, "verified": true}
# 422 {"error": "invalid_code"} or {"error": "expired_or_missing"}
# 429 {"error": "too_many_attempts"}  (the code is discarded)`,
      php: `<?php
$ch = curl_init("${base}/v1/otp/verify");
curl_setopt_array($ch, [
    CURLOPT_POST => true,
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_HTTPHEADER => ["Authorization: Bearer ${key}", "Content-Type: application/json"],
    CURLOPT_POSTFIELDS => json_encode(["phone" => $phone, "code" => $codeTheUserTyped]),
]);
$result = json_decode(curl_exec($ch), true);
$verified = ($result["verified"] ?? false) === true;`,
      node: `const res = await fetch("${base}/v1/otp/verify", {
  method: "POST",
  headers: { Authorization: "Bearer ${key}", "Content-Type": "application/json" },
  body: JSON.stringify({ phone, code: codeTheUserTyped }),
});
const { verified = false } = await res.json();`,
      python: `res = requests.post(
    "${base}/v1/otp/verify",
    headers={"Authorization": "Bearer ${key}"},
    json={"phone": phone, "code": code_the_user_typed},
)
verified = res.json().get("verified", False)`,
    },
    message: {
      curl: `curl -X POST ${base}/v1/messages \\
  -H "Authorization: Bearer ${key}" \\
  -H "Content-Type: application/json" \\
  -H "Idempotency-Key: order-1042-shipped" \\
  -d '{"to": "0712345678", "body": "Your order #1042 has shipped.", "reference": "order-1042"}'`,
      php: `<?php
$ch = curl_init("${base}/v1/messages");
curl_setopt_array($ch, [
    CURLOPT_POST => true,
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_HTTPHEADER => [
        "Authorization: Bearer ${key}",
        "Content-Type: application/json",
        "Idempotency-Key: order-1042-shipped",
    ],
    CURLOPT_POSTFIELDS => json_encode([
        "to" => "0712345678",
        "body" => "Your order #1042 has shipped.",
        "reference" => "order-1042",
    ]),
]);
$message = json_decode(curl_exec($ch), true)["message"];  // keep $message["id"]`,
      node: `const res = await fetch("${base}/v1/messages", {
  method: "POST",
  headers: {
    Authorization: "Bearer ${key}",
    "Content-Type": "application/json",
    "Idempotency-Key": "order-1042-shipped",
  },
  body: JSON.stringify({
    to: "0712345678",
    body: "Your order #1042 has shipped.",
    reference: "order-1042",
  }),
});
const { message } = await res.json(); // keep message.id`,
      python: `res = requests.post(
    "${base}/v1/messages",
    headers={
        "Authorization": "Bearer ${key}",
        "Idempotency-Key": "order-1042-shipped",
    },
    json={"to": "0712345678", "body": "Your order #1042 has shipped.", "reference": "order-1042"},
)
message = res.json()["message"]  # keep message["id"]`,
    },
    webhook: {
      curl: `# Your endpoint receives:
POST https://example.com/sms-events
X-Signature: sha256=<hex HMAC-SHA256 of the raw body, keyed with your webhook secret>

{"event": "message.delivered", "message": {"id": "msg_…", "status": "delivered", "reference": "order-1042", …}}
{"event": "device.disconnected", "device": {"id": 3, "name": "Shop phone"}, "at": "…"}`,
      php: `<?php
$raw = file_get_contents("php://input");
$expected = "sha256=" . hash_hmac("sha256", $raw, getenv("SMS_WEBHOOK_SECRET"));
if (!hash_equals($expected, $_SERVER["HTTP_X_SIGNATURE"] ?? "")) {
    http_response_code(401);
    exit;
}
$event = json_decode($raw, true);
// $event["event"], $event["message"]["id"], $event["message"]["status"]
http_response_code(200);`,
      node: `import crypto from "node:crypto";

// Use the raw request body (e.g. express.raw({ type: "application/json" }))
function isFromGateway(rawBody, signature, secret) {
  const expected = "sha256=" + crypto.createHmac("sha256", secret).update(rawBody).digest("hex");
  return signature?.length === expected.length &&
    crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(signature));
}`,
      python: `import hashlib, hmac

def is_from_gateway(raw_body: bytes, signature: str, secret: str) -> bool:
    expected = "sha256=" + hmac.new(secret.encode(), raw_body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, signature or "")`,
    },
  };
}

export default function DocsPage() {
  const [lang, setLang] = useState<Lang>("curl");
  const base =
    API_URL || (typeof window === "undefined" ? "https://your-gateway" : window.location.origin);
  const ex = examples(base, "sk_YOUR_API_KEY");

  const tabs = (
    <div className="inline-flex rounded-lg border border-zinc-200 p-0.5 dark:border-zinc-800" role="tablist">
      {LANGS.map(({ key, label }) => (
        <button
          key={key}
          type="button"
          role="tab"
          aria-selected={lang === key}
          onClick={() => setLang(key)}
          className={`rounded-md px-3 py-1 text-xs font-medium transition ${
            lang === key
              ? "bg-emerald-600 text-white"
              : "text-zinc-600 hover:bg-zinc-100 dark:text-zinc-400 dark:hover:bg-zinc-900"
          }`}
        >
          {label}
        </button>
      ))}
    </div>
  );

  return (
    <>
      <PageHeader
        title="Integration docs"
        description="Connect your website, app or backend. Everything is JSON over HTTPS."
      />

      <div className="space-y-4">
        <Card
          title="Getting started"
          action={
            <a
              href="/openapi.json"
              target="_blank"
              rel="noreferrer"
              className="inline-flex items-center gap-1.5 rounded-lg border border-zinc-300 px-3 py-1.5 text-sm font-medium hover:bg-zinc-50 dark:border-zinc-700 dark:hover:bg-zinc-900"
            >
              <FileJson className="h-4 w-4" aria-hidden /> OpenAPI spec
            </a>
          }
        >
          <ul className="list-disc space-y-1.5 pl-5 text-sm text-zinc-700 dark:text-zinc-300">
            <li>
              Create an <Link href="/dashboard/keys" className="font-medium text-emerald-700 underline dark:text-emerald-400">API key</Link>{" "}
              and send it as <code>Authorization: Bearer &lt;key&gt;</code>.
            </li>
            <li>
              Start with a <strong>test key</strong> (<code>sk_test_…</code>): it sends nothing, returns OTP
              codes as <code>test_code</code>, and works before your account is approved. Switch to a live key
              when you&apos;re ready.
            </li>
            <li>
              Phone numbers can be international (<code>+254712345678</code>) or local (<code>0712345678</code>,{" "}
              <code>712345678</code>).
            </li>
            <li>
              Messages are queued and sent through your phones. If none is online they wait: OTP codes until they
              expire, other SMS up to 24 hours.
            </li>
            <li>
              Import <code>/openapi.json</code> into Postman, Insomnia or a code generator for a ready-made client.
            </li>
          </ul>
        </Card>

        <Card title="1. Send a verification code" action={tabs}>
          <CodeBlock>{ex.otpSend[lang]}</CodeBlock>
          <p className="mt-3 text-sm text-zinc-700 dark:text-zinc-300">Optional fields:</p>
          <ul className="mt-1 list-disc space-y-1 pl-5 text-sm text-zinc-700 dark:text-zinc-300">
            <li>
              <code>template</code>: your own text, with <code>{"{code}"}</code> and optionally{" "}
              <code>{"{minutes}"}</code>, e.g. <code>&quot;Your Acme code is {"{code}"}&quot;</code>. Set an
              account-wide default in{" "}
              <Link href="/dashboard/settings" className="underline">Settings</Link>.
            </li>
            <li><code>code_length</code>: 4 to 8 digits (default 6).</li>
            <li><code>expires_in</code>: 60 to 3600 seconds (default 300).</li>
            <li><code>reference</code>, <code>callback_url</code>, <code>device_id</code>: as for messages below.</li>
          </ul>
        </Card>

        <Card title="2. Check the code the user typed" action={tabs}>
          <CodeBlock>{ex.otpVerify[lang]}</CodeBlock>
        </Card>

        <Card title="Send any SMS" action={tabs}>
          <CodeBlock>{ex.message[lang]}</CodeBlock>
          <ul className="mt-3 list-disc space-y-1 pl-5 text-sm text-zinc-700 dark:text-zinc-300">
            <li>Bodies are up to 480 characters; long messages are sent in parts and each part counts toward your daily limit.</li>
            <li><code>Idempotency-Key</code> makes retries safe: the same key returns the same message instead of sending twice.</li>
            <li><code>device_id</code> (see the Phones page) sends through a specific phone.</li>
            <li>
              Status: <code>GET /v1/messages/&#123;id&#125;</code> → queued, sending, sent, delivered or failed.
            </li>
          </ul>
        </Card>

        <Card title="Webhooks" action={tabs}>
          <p className="mb-3 text-sm text-zinc-700 dark:text-zinc-300">
            Set a <strong>webhook URL</strong> in <Link href="/dashboard/settings" className="underline">Settings</Link>{" "}
            (or <code>callback_url</code> per message) to be told about <code>message.sent</code>,{" "}
            <code>message.delivered</code>, <code>message.failed</code>, <code>device.connected</code> and{" "}
            <code>device.disconnected</code>. Check the signature with your webhook secret, and answer 2xx; other
            answers are retried with backoff.
          </p>
          <CodeBlock>{ex.webhook[lang]}</CodeBlock>
        </Card>

        <Card title="Gateway status">
          <CodeBlock>{`curl ${base}/v1/status -H "Authorization: Bearer sk_YOUR_API_KEY"

# {"modem": {"status": "ready"}, "devices": [...],
#  "queue": {"pending": 0, "sent_last_24h": 12, "daily_limit": 200}}`}</CodeBlock>
        </Card>
      </div>
    </>
  );
}
