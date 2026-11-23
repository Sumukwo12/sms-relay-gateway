"use client";

import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { getAdminOverview, getAdminUsers } from "../lib/account";
import { useLoad } from "../lib/use-load";
import { Alert, Card, OnlineDot, PageHeader, Spinner } from "../components/ui";

export default function AdminOverviewPage() {
  const { data: o, error } = useLoad(getAdminOverview, 15_000);
  const { data: users } = useLoad(getAdminUsers, 15_000);

  if (error && !o) return <Alert>{error.message}</Alert>;
  if (!o) return <Spinner />;

  const totalUsers = Object.values(o.users).reduce((a, b) => a + (b ?? 0), 0);
  const pending = (users?.users ?? []).filter((u) => u.status === "pending");
  const busiest = [...(users?.users ?? [])]
    .filter((u) => u.sent_last_24h > 0)
    .sort((a, b) => b.sent_last_24h - a.sent_last_24h)
    .slice(0, 5);

  return (
    <>
      <PageHeader title="System overview" description="Everything happening on the gateway, refreshed every 15 seconds." />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Stat label="Users" value={totalUsers}>
          {o.users.approved ?? 0} approved · {o.users.pending ?? 0} pending · {o.users.suspended ?? 0} suspended
        </Stat>
        <Stat label="Phones online" value={`${o.devices.online} / ${o.devices.total}`}>
          Linked phones connected right now
        </Stat>
        <Stat label="SMS parts sent, 24h" value={o.messages.sent_last_24h}>
          {o.messages.queued} waiting in the queue
        </Stat>
        <Card>
          <p className="text-sm text-zinc-500">Server-level route</p>
          <div className="mt-2"><OnlineDot online={o.server_gateway_online} /></div>
          <p className="mt-1 text-xs text-zinc-500">API_KEYS from the server config use this</p>
        </Card>
      </div>

      <div className="mt-4 grid gap-4 lg:grid-cols-2">
        <Card
          title={`Waiting for approval (${pending.length})`}
          action={<MoreLink href="/admin/users">Manage users</MoreLink>}
        >
          {pending.length === 0 ? (
            <p className="text-sm text-zinc-500">Nobody is waiting.</p>
          ) : (
            <ul className="divide-y divide-zinc-100 text-sm dark:divide-zinc-800">
              {pending.slice(0, 8).map((u) => (
                <li key={u.id} className="py-2">
                  <p className="font-medium">{u.email}</p>
                  <p className="text-xs text-zinc-500">{u.name ?? "No name"} · signed up {new Date(u.created_at).toLocaleDateString()}</p>
                </li>
              ))}
            </ul>
          )}
        </Card>

        <Card title="Busiest users, 24h" action={<MoreLink href="/admin/messages">All messages</MoreLink>}>
          {busiest.length === 0 ? (
            <p className="text-sm text-zinc-500">No messages sent in the last 24 hours.</p>
          ) : (
            <ul className="divide-y divide-zinc-100 text-sm dark:divide-zinc-800">
              {busiest.map((u) => (
                <li key={u.id} className="flex items-center justify-between py-2">
                  <span className="truncate">{u.email}</span>
                  <span className="text-xs text-zinc-500">
                    {u.sent_last_24h} / {u.daily_limit}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>
    </>
  );
}

function Stat({ label, value, children }: { label: string; value: number | string; children: React.ReactNode }) {
  return (
    <Card>
      <p className="text-sm text-zinc-500">{label}</p>
      <p className="mt-2 text-2xl font-semibold">{value}</p>
      <p className="mt-1 text-xs text-zinc-500">{children}</p>
    </Card>
  );
}

function MoreLink({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <Link href={href} className="inline-flex items-center gap-1 text-sm font-medium text-emerald-700 dark:text-emerald-400">
      {children} <ArrowRight className="h-4 w-4" aria-hidden />
    </Link>
  );
}
