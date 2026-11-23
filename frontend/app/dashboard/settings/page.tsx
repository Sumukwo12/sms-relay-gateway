"use client";

import { useState, type FormEvent } from "react";
import { changePassword, getOverview, rotateWebhookSecret, updateSettings } from "../../lib/account";
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
        <IntegrationSettings />
        <WebhookSecret />
        <PasswordForm />
      </div>
    </>
  );
}

function IntegrationSettings() {
  const { data } = useLoad(getOverview);
  // Local edits, falling back to the saved values until the user types
  const [webhookUrl, setWebhookUrl] = useState<string | null>(null);
  const [template, setTemplate] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [result, setResult] = useState<{ ok: boolean; text: string } | null>(null);

  const urlValue = webhookUrl ?? data?.webhook_url ?? "";
  const templateValue = template ?? data?.otp_template ?? "";

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setPending(true);
    const res = await updateSettings({ webhook_url: urlValue, otp_template: templateValue });
    setPending(false);
    setResult(res.ok ? { ok: true, text: "Saved." } : { ok: false, text: res.error.message });
  }

  return (
    <Card title="Integration" description="Defaults for every API call; a request can still override them.">
      <form onSubmit={onSubmit} className="space-y-4">
        <Field
          id="webhook-url"
          label="Webhook URL"
          type="url"
          placeholder="https://example.com/sms-events"
          value={urlValue}
          onChange={(e) => setWebhookUrl(e.target.value)}
          hint="Receives message.sent / delivered / failed for messages without their own callback_url, plus device.connected / device.disconnected when a phone comes and goes. Leave empty to turn off."
        />
        <Field
          id="otp-template"
          label="Verification SMS text"
          placeholder="Your Acme code is {code}. It expires in {minutes} minutes."
          value={templateValue}
          onChange={(e) => setTemplate(e.target.value)}
          hint="Must contain {code}; {minutes} is replaced by the expiry. Leave empty for the default."
        />
        {result && <Alert tone={result.ok ? "success" : "error"}>{result.text}</Alert>}
        <Button type="submit" pending={pending} disabled={!data}>Save</Button>
      </form>
    </Card>
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
