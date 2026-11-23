"use client";

import { useState } from "react";
import {
  getAdminDevices,
  getAdminOverview,
  getAdminUsers,
  updateAdminUser,
  type AdminUser,
  type UserStatus,
} from "../../lib/account";
import { useLoad } from "../../lib/use-load";
import { Alert, Badge, Button, Card, OnlineDot, PageHeader, Spinner, timeAgo } from "../../components/ui";
import { useSession } from "../session";

const STATUS_TONE: Record<UserStatus, "amber" | "green" | "red"> = {
  pending: "amber",
  approved: "green",
  suspended: "red",
};

export default function AdminPage() {
  const { user } = useSession();
  const overview = useLoad(getAdminOverview, 15_000);
  const users = useLoad(getAdminUsers, 15_000);
  const devices = useLoad(getAdminDevices, 15_000);
  const [filter, setFilter] = useState<UserStatus | "all">("all");

  if (user.role !== "admin") return <Alert>Administrators only.</Alert>;

  const o = overview.data;
  const list = (users.data?.users ?? []).filter((u) => filter === "all" || u.status === filter);
  const pendingCount = o?.users.pending ?? 0;

  function reloadAll() {
    overview.reload();
    users.reload();
  }

  return (
    <>
      <PageHeader title="Admin" description="Approve accounts, set limits and watch the gateway." />

      {o && (
        <div className="mb-4 grid gap-4 sm:grid-cols-4">
          <Card>
            <p className="text-sm text-zinc-500">Users</p>
            <p className="mt-2 text-lg font-semibold">
              {Object.values(o.users).reduce((a, b) => a + (b ?? 0), 0)}
            </p>
            {pendingCount > 0 && <p className="text-xs text-amber-600">{pendingCount} waiting for approval</p>}
          </Card>
          <Card>
            <p className="text-sm text-zinc-500">Phones online</p>
            <p className="mt-2 text-lg font-semibold">
              {o.devices.online} <span className="text-sm font-normal text-zinc-500">/ {o.devices.total}</span>
            </p>
          </Card>
          <Card>
            <p className="text-sm text-zinc-500">SMS parts, last 24h</p>
            <p className="mt-2 text-lg font-semibold">{o.messages.sent_last_24h}</p>
            <p className="text-xs text-zinc-500">{o.messages.queued} queued</p>
          </Card>
          <Card>
            <p className="text-sm text-zinc-500">Server-level route</p>
            <p className="mt-2"><OnlineDot online={o.server_gateway_online} /></p>
            <p className="mt-1 text-xs text-zinc-500">Demo page and API_KEYS</p>
          </Card>
        </div>
      )}

      <Card
        title="Users"
        className="mb-4"
        action={
          <select
            value={filter}
            onChange={(e) => setFilter(e.target.value as UserStatus | "all")}
            aria-label="Filter by status"
            className="rounded-lg border border-zinc-300 bg-transparent px-2 py-1 text-sm dark:border-zinc-700"
          >
            <option value="all">All</option>
            <option value="pending">Pending</option>
            <option value="approved">Approved</option>
            <option value="suspended">Suspended</option>
          </select>
        }
      >
        {users.error && <Alert>{users.error.message}</Alert>}
        {!users.data && !users.error && <Spinner />}
        {users.data && list.length === 0 && <p className="text-sm text-zinc-500">No users.</p>}
        {list.length > 0 && (
          <ul className="divide-y divide-zinc-100 dark:divide-zinc-800">
            {list.map((u) => (
              <UserRow key={u.id} user={u} isMe={u.id === user.id} onChange={reloadAll} />
            ))}
          </ul>
        )}
      </Card>

      <Card title="All phones">
        {!devices.data && <Spinner />}
        {devices.data && devices.data.devices.length === 0 && <p className="text-sm text-zinc-500">No phones linked yet.</p>}
        {devices.data && devices.data.devices.length > 0 && (
          <ul className="divide-y divide-zinc-100 text-sm dark:divide-zinc-800">
            {devices.data.devices.map((d) => (
              <li key={d.id} className="flex flex-wrap items-center justify-between gap-2 py-2.5">
                <div>
                  <p className="font-medium">{d.name} <span className="font-normal text-zinc-500">· {d.owner?.email}</span></p>
                  <p className="text-xs text-zinc-500">
                    {[d.model, d.app_version && `app ${d.app_version}`, d.battery != null && `battery ${d.battery}%`]
                      .filter(Boolean)
                      .join(" · ")}
                    {!d.online && ` · last seen ${timeAgo(d.last_seen_at)}`}
                  </p>
                </div>
                <OnlineDot online={d.online} />
              </li>
            ))}
          </ul>
        )}
      </Card>
    </>
  );
}

function UserRow({ user, isMe, onChange }: { user: AdminUser; isMe: boolean; onChange: () => void }) {
  const [limit, setLimit] = useState(user.custom_daily_limit?.toString() ?? "");
  const [pending, setPending] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function update(label: string, changes: Parameters<typeof updateAdminUser>[1]) {
    setPending(label);
    setError(null);
    const res = await updateAdminUser(user.id, changes);
    setPending(null);
    if (res.ok) onChange();
    else setError(res.error.message);
  }

  return (
    <li className="py-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="font-medium">
            {user.email} {isMe && <span className="text-xs font-normal text-zinc-500">(you)</span>}
          </p>
          <p className="mt-1 flex flex-wrap items-center gap-2 text-xs text-zinc-500">
            <Badge tone={STATUS_TONE[user.status]}>{user.status}</Badge>
            {user.role === "admin" && <Badge tone="blue">admin</Badge>}
            {user.name && <span>{user.name}</span>}
            <span>joined {timeAgo(user.created_at)}</span>
            <span>· {user.sent_last_24h}/{user.daily_limit} today</span>
            <OnlineDot online={user.online} />
          </p>
        </div>

        {!isMe && (
          <div className="flex flex-wrap items-center gap-2">
            {user.status !== "approved" && (
              <Button onClick={() => update("approve", { status: "approved" })} pending={pending === "approve"} className="px-3 py-1.5">
                Approve
              </Button>
            )}
            {user.status !== "suspended" && (
              <Button variant="danger" onClick={() => update("suspend", { status: "suspended" })} pending={pending === "suspend"} className="px-3 py-1.5">
                Suspend
              </Button>
            )}
            <Button
              variant="secondary"
              onClick={() => update("role", { role: user.role === "admin" ? "user" : "admin" })}
              pending={pending === "role"}
              className="px-3 py-1.5"
            >
              {user.role === "admin" ? "Make user" : "Make admin"}
            </Button>
          </div>
        )}
      </div>

      <form
        className="mt-3 flex items-center gap-2 text-xs"
        onSubmit={(e) => {
          e.preventDefault();
          update("limit", { daily_limit: limit.trim() === "" ? null : Number(limit) });
        }}
      >
        <label htmlFor={`limit-${user.id}`} className="text-zinc-500">Daily limit</label>
        <input
          id={`limit-${user.id}`}
          type="number"
          min={0}
          placeholder="default"
          value={limit}
          onChange={(e) => setLimit(e.target.value)}
          className="w-24 rounded-md border border-zinc-300 bg-transparent px-2 py-1 dark:border-zinc-700"
        />
        <Button type="submit" variant="ghost" pending={pending === "limit"} className="px-2 py-1 text-xs">
          Save
        </Button>
      </form>
      {error && <div className="mt-2"><Alert>{error}</Alert></div>}
    </li>
  );
}
