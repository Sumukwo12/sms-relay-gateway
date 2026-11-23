"use client";

import { useState, type FormEvent } from "react";
import { changePassword, getOverview, rotateWebhookSecret } from "../../lib/account";
import { useLoad } from "../../lib/use-load";
import { Alert, Button, Card, CopyButton, Field, PageHeader } from "../../components/ui";
import { useSession } from "../session";

export default function SettingsPage() {
  const { user } = useSession();

  return (
    <>
      <PageHeader title="Settings" />
      <div className="space-y-4">
        <Card title="Account">
          <dl className="grid gap-3 text-sm sm:grid-cols-3">
            <div>
              <dt className="text-zinc-500">Email</dt>
              <dd className="font-medium">{user.email}</dd>
            </div>
            <div>
              <dt className="text-zinc-500">Status</dt>
              <dd className="font-medium capitalize">{user.status}</dd>
            </div>
            <div>
              <dt className="text-zinc-500">Daily limit</dt>
              <dd className="font-medium">{user.daily_limit} SMS parts / 24h</dd>
            </div>
          </dl>
        </Card>
        <WebhookSecret />
        <PasswordForm />
      </div>
    </>
  );
}

function WebhookSecret() {
  const { data, reload } = useLoad(getOverview);
  const [revealed, setRevealed] = useState(false);
  const [pending, setPending] = useState(false);

  async function rotate() {
    if (!window.confirm("Create a new secret? Webhooks are signed with the new one immediately.")) return;
    setPending(true);
    await rotateWebhookSecret();
    setPending(false);
    setRevealed(true);
    reload();
  }

  const secret = data?.webhook_secret ?? "";

  return (
    <Card
      title="Webhook secret"
      description="Delivery webhooks carry X-Signature: an HMAC-SHA256 of the body, keyed with this secret."
    >
      <div className="flex flex-wrap items-center gap-2">
        <code className="rounded bg-zinc-100 px-2 py-1 font-mono text-xs dark:bg-zinc-900">
          {revealed ? secret : secret.replace(/./g, "•").slice(0, 32)}
        </code>
        <Button variant="ghost" onClick={() => setRevealed(!revealed)} className="px-2 py-1 text-xs">
          {revealed ? "Hide" : "Show"}
        </Button>
        {secret && <CopyButton value={secret} />}
        <Button variant="secondary" onClick={rotate} pending={pending} className="px-3 py-1 text-xs">
          Rotate
        </Button>
      </div>
    </Card>
  );
}

function PasswordForm() {
  const [current, setCurrent] = useState("");
  const [next, setNext] = useState("");
  const [pending, setPending] = useState(false);
  const [result, setResult] = useState<{ ok: boolean; text: string } | null>(null);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setPending(true);
    const res = await changePassword(current, next);
    setPending(false);

    if (res.ok) {
      setCurrent("");
      setNext("");
      setResult({ ok: true, text: "Password changed. Other browsers have been signed out." });
    } else {
      setResult({ ok: false, text: res.error.message });
    }
  }

  return (
    <Card title="Change password">
      <form onSubmit={onSubmit} className="max-w-sm space-y-3">
        <Field id="current-password" label="Current password" type="password" autoComplete="current-password" value={current} onChange={(e) => setCurrent(e.target.value)} />
        <Field id="new-password" label="New password" type="password" autoComplete="new-password" value={next} onChange={(e) => setNext(e.target.value)} hint="At least 8 characters." />
        {result && <Alert tone={result.ok ? "success" : "error"}>{result.text}</Alert>}
        <Button type="submit" pending={pending} disabled={!current || !next}>Change password</Button>
      </form>
    </Card>
  );
}
