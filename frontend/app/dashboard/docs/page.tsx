"use client";

import Link from "next/link";
import { API_URL } from "../../lib/api";
import { Card, CodeBlock, PageHeader } from "../../components/ui";

export default function DocsPage() {
  const base = API_URL || (typeof window === "undefined" ? "https://your-gateway" : window.location.origin);
  const key = "sk_YOUR_API_KEY";

  return (
    <>
      <PageHeader
        title="Integration docs"
        description="Call the gateway from your own systems. Everything is JSON over HTTPS."
      />

      <div className="space-y-4">
        <Card title="Authentication">
          <p className="text-sm text-zinc-700 dark:text-zinc-300">
            Send an <Link href="/dashboard/keys" className="font-medium text-emerald-700 underline dark:text-emerald-400">API key</Link>{" "}
            with every request as <code>Authorization: Bearer &lt;key&gt;</code>. Messages are queued
            and sent through your phones; if no phone is online they wait (OTP codes until they
            expire, other SMS up to 24 hours).
          </p>
        </Card>

        <Card title="Verify a phone number (OTP)" description="The gateway creates the code, texts it, and checks it.">
          <div className="space-y-3">
            <CodeBlock>{`# 1. Send a code (202 Accepted)
curl -X POST ${base}/v1/otp/send \\
  -H "Authorization: Bearer ${key}" \\
  -H "Content-Type: application/json" \\
  -d '{"phone": "+254712345678"}'`}</CodeBlock>
            <CodeBlock>{`# 2. Check the code the user typed in
curl -X POST ${base}/v1/otp/verify \\
  -H "Authorization: Bearer ${key}" \\
  -H "Content-Type: application/json" \\
  -d '{"phone": "+254712345678", "code": "483921"}'

# 200 {"success": true, "verified": true}
# 422 {"error": "invalid_code"} · {"error": "expired_or_missing"}
# 429 {"error": "too_many_attempts"}  (the code is discarded)`}</CodeBlock>
          </div>
        </Card>

        <Card title="Send any SMS">
          <div className="space-y-3">
            <CodeBlock>{`curl -X POST ${base}/v1/messages \\
  -H "Authorization: Bearer ${key}" \\
  -H "Content-Type: application/json" \\
  -H "Idempotency-Key: order-1042-shipped" \\
  -d '{
    "to": "+254712345678",
    "body": "Your order #1042 has shipped.",
    "reference": "order-1042",
    "callback_url": "https://example.com/sms-status"
  }'`}</CodeBlock>
            <CodeBlock>{`# Check its status: queued → sending → sent → delivered (or failed)
curl ${base}/v1/messages/msg_0123456789abcdef0123 \\
  -H "Authorization: Bearer ${key}"`}</CodeBlock>
            <ul className="list-disc space-y-1 pl-5 text-sm text-zinc-700 dark:text-zinc-300">
              <li>Numbers are in international format, e.g. <code>+254712345678</code>.</li>
              <li>Bodies are up to 480 characters; long messages are sent in parts and count once per part toward your daily limit.</li>
              <li><code>Idempotency-Key</code> makes retries safe: the same key returns the same message instead of sending twice.</li>
              <li>Add <code>&quot;device_id&quot;</code> (see the Phones page) to send through a specific phone.</li>
            </ul>
          </div>
        </Card>

        <Card title="Delivery webhooks" description="With callback_url, the gateway POSTs each status change to you.">
          <div className="space-y-3">
            <CodeBlock>{`POST https://example.com/sms-status
X-Signature: sha256=<hex HMAC-SHA256 of the raw body>

{"event": "message.delivered", "message": {"id": "msg_…", "status": "delivered", ...}}`}</CodeBlock>
            <p className="text-sm text-zinc-700 dark:text-zinc-300">
              Events: <code>message.sent</code>, <code>message.delivered</code>, <code>message.failed</code>.
              Verify the signature with your webhook secret from{" "}
              <Link href="/dashboard/settings" className="font-medium text-emerald-700 underline dark:text-emerald-400">Settings</Link>.
              Answer 2xx; other answers are retried with backoff.
            </p>
            <CodeBlock>{`// Node.js
import crypto from "node:crypto";

function isFromGateway(rawBody, signatureHeader, secret) {
  const expected = "sha256=" + crypto.createHmac("sha256", secret).update(rawBody).digest("hex");
  return crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(signatureHeader ?? ""));
}`}</CodeBlock>
          </div>
        </Card>

        <Card title="Gateway status">
          <CodeBlock>{`curl ${base}/v1/status -H "Authorization: Bearer ${key}"

# {"modem": {"status": "ready"}, "devices": [...],
#  "queue": {"pending": 0, "sent_last_24h": 12, "daily_limit": 200}}`}</CodeBlock>
        </Card>
      </div>
    </>
  );
}
