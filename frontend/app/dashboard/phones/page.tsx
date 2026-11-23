"use client";

import { useState } from "react";
import { Battery, Download, Pencil, Signal, Trash2 } from "lucide-react";
import { getDevices, removeDevice, renameDevice, type Device } from "../../lib/account";
import { useLoad } from "../../lib/use-load";
import { Alert, Button, Card, OnlineDot, PageHeader, Spinner, timeAgo } from "../../components/ui";
import { useSession } from "../session";

import { APP_DOWNLOAD_URL, APP_SIZE, APP_VERSION } from "../../lib/site";

export default function PhonesPage() {
  const { user } = useSession();
  const { data, error, reload } = useLoad(getDevices, 10_000);
  const server = typeof window === "undefined" ? "" : window.location.origin;

  return (
    <>
      <PageHeader
        title="Phones"
        description="Android phones running the SMS Relay app. Your messages go out through them, using their SIM."
      />

      <Card title="Link a phone" className="mb-4">
        <ol className="list-decimal space-y-2 pl-5 text-sm text-zinc-700 dark:text-zinc-300">
          <li>
            Install the <strong>SMS Relay</strong> app on an Android phone with a SIM card.
            {APP_DOWNLOAD_URL ? (
              <a
                href={APP_DOWNLOAD_URL}
                className="ml-2 inline-flex items-center gap-1 font-medium text-emerald-700 hover:underline dark:text-emerald-400"
              >
                <Download className="h-4 w-4" aria-hidden /> Download SMS Relay {APP_VERSION} (APK, {APP_SIZE})
              </a>
            ) : (
              " Ask your administrator for the APK."
            )}
          </li>
          <li>Allow SMS, Phone and Notification permissions when asked.</li>
          <li>
            In the app, sign in with <strong>{user.email}</strong>
            {server && (
              <>
                {" "}on server <code className="rounded bg-zinc-100 px-1 py-0.5 text-xs dark:bg-zinc-800">{server}</code>
              </>
            )}
            . The phone appears below and turns <em>Online</em>.
          </li>
          <li>
            On Xiaomi/Redmi/Samsung phones, turn on <em>Autostart</em> and set battery to <em>No
            restrictions</em> for SMS Relay, or it may stop in the background.
          </li>
        </ol>
      </Card>

      {error && !data && <Alert>{error.message}</Alert>}
      {!data && !error && <Spinner />}

      {data && (
        <Card title={`Your phones (${data.devices.length})`}>
          {data.devices.length === 0 ? (
            <p className="text-sm text-zinc-500">No phone linked yet. Follow the steps above.</p>
          ) : (
            <ul className="divide-y divide-zinc-100 dark:divide-zinc-800">
              {data.devices.map((device) => (
                <DeviceRow key={device.id} device={device} onChange={reload} />
              ))}
            </ul>
          )}
          {data.devices.length > 1 && (
            <p className="mt-4 text-xs text-zinc-500">
              Messages go out through the phone that connected most recently, unless your API call
              passes a <code>device_id</code>.
            </p>
          )}
        </Card>
      )}
    </>
  );
}

function DeviceRow({ device, onChange }: { device: Device; onChange: () => void }) {
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(device.name);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save() {
    setPending(true);
    const res = await renameDevice(device.id, name);
    setPending(false);
    if (res.ok) {
      setEditing(false);
      onChange();
    } else {
      setError(res.error.message);
    }
  }

  async function remove() {
    if (!window.confirm(`Sign "${device.name}" out? It stops sending until you sign in on it again.`)) return;
    setPending(true);
    const res = await removeDevice(device.id);
    setPending(false);
    if (res.ok) onChange();
    else setError(res.error.message);
  }

  return (
    <li className="py-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          {editing ? (
            <div className="flex gap-2">
              <input
                value={name}
                onChange={(e) => setName(e.target.value)}
                aria-label="Phone name"
                className="rounded-lg border border-zinc-300 bg-transparent px-2 py-1 text-sm dark:border-zinc-700"
                autoFocus
              />
              <Button onClick={save} pending={pending} className="py-1">Save</Button>
              <Button variant="ghost" onClick={() => setEditing(false)} className="py-1">Cancel</Button>
            </div>
          ) : (
            <p className="font-medium">{device.name}</p>
          )}
          <p className="mt-1 text-xs text-zinc-500">
            ID {device.id}
            {device.model && ` · ${device.model}`}
            {device.app_version && ` · app ${device.app_version}`}
            {" · "}
            {device.online ? "connected now" : `last seen ${timeAgo(device.last_seen_at)}`}
          </p>
          {device.online && (device.battery != null || device.signal != null) && (
            <p className="mt-1 flex gap-3 text-xs text-zinc-500">
              {device.battery != null && (
                <span className="inline-flex items-center gap-1">
                  <Battery className="h-3.5 w-3.5" aria-hidden /> {device.battery}%
                  {device.charging ? " (charging)" : ""}
                </span>
              )}
              {device.signal != null && (
                <span className="inline-flex items-center gap-1">
                  <Signal className="h-3.5 w-3.5" aria-hidden /> {device.signal}/4
                </span>
              )}
            </p>
          )}
        </div>
        <div className="flex items-center gap-2">
          <OnlineDot online={device.online} />
          {!editing && (
            <Button variant="ghost" onClick={() => setEditing(true)} aria-label="Rename" className="px-2">
              <Pencil className="h-4 w-4" aria-hidden />
            </Button>
          )}
          <Button variant="danger" onClick={remove} pending={pending} aria-label="Sign out phone" className="px-2">
            <Trash2 className="h-4 w-4" aria-hidden />
          </Button>
        </div>
      </div>
      {error && <div className="mt-2"><Alert>{error}</Alert></div>}
    </li>
  );
}
