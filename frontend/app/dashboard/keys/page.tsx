"use client";

import { useState, type FormEvent } from "react";
import { Trash2 } from "lucide-react";
import { createApiKey, getApiKeys, revokeApiKey } from "../../lib/account";
import { useLoad } from "../../lib/use-load";
import { Alert, Button, Card, CopyButton, Field, PageHeader, Spinner, timeAgo } from "../../components/ui";

export default function KeysPage() {
  const { data, error, reload } = useLoad(getApiKeys);
  const [name, setName] = useState("");
  const [pending, setPending] = useState(false);
  const [created, setCreated] = useState<{ name: string; key: string } | null>(null);
  const [formError, setFormError] = useState<string | null>(null);

  async function onCreate(e: FormEvent) {
    e.preventDefault();
    setPending(true);
    setFormError(null);
    const res = await createApiKey(name.trim());
    setPending(false);

    if (res.ok) {
      setCreated({ name: res.data.api_key.name, key: res.data.key });
      setName("");
      reload();
    } else {
      setFormError(res.error.message);
    }
  }

  async function onRevoke(id: number, keyName: string) {
    if (!window.confirm(`Revoke "${keyName}"? Systems using it stop working immediately.`)) return;
    const res = await revokeApiKey(id);
    if (res.ok) reload();
    else setFormError(res.error.message);
  }

  return (
    <>
      <PageHeader
        title="API keys"
        description="Each system that sends SMS through your gateway gets its own key. Keep them secret, like passwords."
      />

      <Card title="Create a key" className="mb-4">
        <form onSubmit={onCreate} className="flex flex-col gap-3 sm:flex-row sm:items-end">
          <div className="flex-1">
            <Field
              id="key-name"
              label="Name"
              placeholder="e.g. Shop website"
              value={name}
              onChange={(e) => setName(e.target.value)}
              hint="So you can tell your keys apart."
            />
          </div>
          <Button type="submit" pending={pending} disabled={!name.trim()} className="sm:mb-5">
            Create key
          </Button>
        </form>

        {formError && <div className="mt-3"><Alert>{formError}</Alert></div>}

        {created && (
          <div className="mt-4">
            <Alert tone="success">
              <p className="font-medium">Key &ldquo;{created.name}&rdquo; created. Copy it now: it won&apos;t be shown again.</p>
              <div className="mt-2 flex items-center gap-2">
                <code className="break-all rounded bg-white px-2 py-1 font-mono text-xs text-zinc-900 dark:bg-zinc-900 dark:text-zinc-100">
                  {created.key}
                </code>
                <CopyButton value={created.key} />
              </div>
            </Alert>
          </div>
        )}
      </Card>

      {error && !data && <Alert>{error.message}</Alert>}
      {!data && !error && <Spinner />}

      {data && (
        <Card title={`Active keys (${data.api_keys.length})`}>
          {data.api_keys.length === 0 ? (
            <p className="text-sm text-zinc-500">No keys yet.</p>
          ) : (
            <ul className="divide-y divide-zinc-100 dark:divide-zinc-800">
              {data.api_keys.map((key) => (
                <li key={key.id} className="flex items-center justify-between gap-3 py-3">
                  <div className="min-w-0">
                    <p className="font-medium">{key.name}</p>
                    <p className="text-xs text-zinc-500">
                      <code>{key.prefix}…</code> · created {timeAgo(key.created_at)} · last used{" "}
                      {timeAgo(key.last_used_at)}
                    </p>
                  </div>
                  <Button variant="danger" onClick={() => onRevoke(key.id, key.name)} className="px-3">
                    <Trash2 className="h-4 w-4" aria-hidden /> Revoke
                  </Button>
                </li>
              ))}
            </ul>
          )}
        </Card>
      )}
    </>
  );
}
