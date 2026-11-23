"use client";

import Link from "next/link";
import { useState, type FormEvent } from "react";
import {
  consoleOtpSend,
  consoleOtpVerify,
  consoleSms,
  getDevices,
  type Device,
  type Message,
} from "../../lib/account";
import type { ApiError } from "../../lib/api";
import { useLoad } from "../../lib/use-load";
import { Alert, Button, Card, Field, PageHeader } from "../../components/ui";
import { useSession } from "../session";

export default function ConsolePage() {
  const { user } = useSession();
  const { data } = useLoad(getDevices);
  const devices = data?.devices ?? [];
  const [deviceId, setDeviceId] = useState<number | null>(null);

  return (
    <>
      <PageHeader
        title="Test console"
        description="Try your gateway before integrating: these messages go out through your phone like API calls do."
      />

      {user.status !== "approved" && (
        <div className="mb-4">
          <Alert tone="warning">Sending is available once an administrator approves your account.</Alert>
        </div>
      )}
      {data && devices.length === 0 && (
        <div className="mb-4">
          <Alert tone="info">
            Link a phone first on the <Link href="/dashboard/phones" className="underline">Phones</Link> page,
            or messages will wait in the queue.
          </Alert>
        </div>
      )}

      {devices.length > 1 && (
        <Card className="mb-4">
          <label htmlFor="device" className="block text-sm font-medium">Send through</label>
          <select
            id="device"
            value={deviceId ?? ""}
            onChange={(e) => setDeviceId(e.target.value ? Number(e.target.value) : null)}
            className="mt-1.5 w-full rounded-lg border border-zinc-300 bg-transparent px-3 py-2 text-sm dark:border-zinc-700"
          >
            <option value="">Most recently connected phone</option>
            {devices.map((d: Device) => (
              <option key={d.id} value={d.id}>
                {d.name} {d.online ? "(online)" : "(offline)"}
              </option>
            ))}
          </select>
        </Card>
      )}

      <div className="grid gap-4 lg:grid-cols-2">
        <SmsForm deviceId={deviceId} />
        <OtpForm deviceId={deviceId} />
      </div>
    </>
  );
}

function queuedNote(message: Message) {
  return `Queued as ${message.id}. Follow its status on the Messages page.`;
}

function SmsForm({ deviceId }: { deviceId: number | null }) {
  const [to, setTo] = useState("");
  const [body, setBody] = useState("Hello from my SMS gateway!");
  const [pending, setPending] = useState(false);
  const [result, setResult] = useState<{ ok: boolean; text: string } | null>(null);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setPending(true);
    const res = await consoleSms(to.trim(), body, deviceId);
    setPending(false);
    setResult(res.ok ? { ok: true, text: queuedNote(res.data.message) } : { ok: false, text: res.error.message });
  }

  return (
    <Card title="Send an SMS" description="Same as POST /v1/messages.">
      <form onSubmit={onSubmit} className="space-y-3">
        <Field id="sms-to" label="To" type="tel" placeholder="+254712345678" value={to} onChange={(e) => setTo(e.target.value)} />
        <div>
          <label htmlFor="sms-body" className="block text-sm font-medium">Message</label>
          <textarea
            id="sms-body"
            rows={3}
            maxLength={480}
            value={body}
            onChange={(e) => setBody(e.target.value)}
            className="mt-1.5 w-full rounded-lg border border-zinc-300 bg-transparent px-3 py-2 text-sm outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-500/20 dark:border-zinc-700"
          />
          <p className="text-xs text-zinc-500">{body.length}/480 characters</p>
        </div>
        {result && <Alert tone={result.ok ? "success" : "error"}>{result.text}</Alert>}
        <Button type="submit" pending={pending} disabled={!to.trim() || !body.trim()}>Send SMS</Button>
      </form>
    </Card>
  );
}

function OtpForm({ deviceId }: { deviceId: number | null }) {
  const [phone, setPhone] = useState("");
  const [code, setCode] = useState("");
  const [sent, setSent] = useState(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  async function onSend(e: FormEvent) {
    e.preventDefault();
    setPending(true);
    setError(null);
    setNotice(null);
    const res = await consoleOtpSend(phone.trim(), deviceId);
    setPending(false);

    if (res.ok) {
      setSent(true);
      setNotice(`Code sent. It is valid for ${Math.round(res.data.expires_in_seconds / 60)} minutes.`);
    } else {
      setError(res.error);
    }
  }

  async function onVerify(e: FormEvent) {
    e.preventDefault();
    setPending(true);
    setError(null);
    const res = await consoleOtpVerify(phone.trim(), code.trim());
    setPending(false);

    if (res.ok) {
      setNotice("Verified! The code matched.");
      setSent(false);
      setCode("");
    } else {
      setError(res.error);
    }
  }

  return (
    <Card title="Verification code (OTP)" description="Same as POST /v1/otp/send and /v1/otp/verify.">
      {!sent ? (
        <form onSubmit={onSend} className="space-y-3">
          <Field id="otp-phone" label="Phone number" type="tel" placeholder="+254712345678" value={phone} onChange={(e) => setPhone(e.target.value)} />
          {notice && <Alert tone="success">{notice}</Alert>}
          {error && <Alert>{error.message}</Alert>}
          <Button type="submit" pending={pending} disabled={!phone.trim()}>Send code</Button>
        </form>
      ) : (
        <form onSubmit={onVerify} className="space-y-3">
          <Field
            id="otp-code"
            label={`Code sent to ${phone}`}
            inputMode="numeric"
            autoComplete="one-time-code"
            maxLength={6}
            value={code}
            onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
            autoFocus
          />
          {notice && <Alert tone="info">{notice}</Alert>}
          {error && <Alert>{error.message}</Alert>}
          <div className="flex gap-2">
            <Button type="submit" pending={pending} disabled={code.length !== 6}>Verify</Button>
            <Button type="button" variant="ghost" onClick={() => { setSent(false); setError(null); setNotice(null); }}>
              Start over
            </Button>
          </div>
        </form>
      )}
    </Card>
  );
}
