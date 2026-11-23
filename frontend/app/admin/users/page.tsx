"use client";

import { useState } from "react";
import { getAdminUsers, updateAdminUser, type AdminUser, type UserStatus } from "../../lib/account";
import { useLoad } from "../../lib/use-load";
import { Alert, Badge, Button, Card, OnlineDot, PageHeader, Spinner, timeAgo } from "../../components/ui";
import { useSession } from "../../dashboard/session";

const STATUS_TONE: Record<UserStatus, "amber" | "green" | "red"> = {
  pending: "amber",
  approved: "green",
  suspended: "red",
};

export default function AdminUsersPage() {
  const { user: me } = useSession();
  const { data, error, reload } = useLoad(getAdminUsers, 15_000);
  const [filter, setFilter] = useState<UserStatus | "all">("all");
  const [query, setQuery] = useState("");

  const list = (data?.users ?? []).filter(
    (u) =>
      (filter === "all" || u.status === filter) &&
      (query === "" || `${u.email} ${u.name ?? ""}`.toLowerCase().includes(query.toLowerCase())),
  );

  return (
    <>
      <PageHeader
        title="Users"
        description="New sign-ups wait here until you approve them. Suspending signs a user out everywhere and disconnects their phones."
      />

      <Card
        title={`${list.length} user${list.length === 1 ? "" : "s"}`}
        action={
          <div className="flex gap-2">
            <input
              type="search"
              placeholder="Search email or name"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              aria-label="Search users"
              className="rounded-lg border border-zinc-300 bg-transparent px-2 py-1 text-sm dark:border-zinc-700"
            />
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
          </div>
        }
      >
        {error && !data && <Alert>{error.message}</Alert>}
        {!data && !error && <Spinner />}
        {data && list.length === 0 && <p className="text-sm text-zinc-500">No users match.</p>}
        {list.length > 0 && (
          <ul className="divide-y divide-zinc-100 dark:divide-zinc-800">
            {list.map((u) => (
              <UserRow key={u.id} user={u} isMe={u.id === me.id} onChange={reload} />
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

  async function update(label: string, changes: Parameters<typeof updateAdminUser>[1], confirm?: string) {
    if (confirm && !window.confirm(confirm)) return;
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
            <span>· {user.sent_last_24h}/{user.daily_limit} sent today</span>
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
              <Button
                variant="danger"
                onClick={() => update("suspend", { status: "suspended" }, `Suspend ${user.email}? They are signed out and their phones disconnect.`)}
                pending={pending === "suspend"}
                className="px-3 py-1.5"
              >
                Suspend
              </Button>
            )}
            <Button
              variant="secondary"
              onClick={() =>
                update(
                  "role",
                  { role: user.role === "admin" ? "user" : "admin" },
                  user.role === "admin" ? undefined : `Make ${user.email} an admin? They will see and manage everything.`,
                )
              }
              pending={pending === "role"}
              className="px-3 py-1.5"
            >
              {user.role === "admin" ? "Remove admin" : "Make admin"}
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
        <label htmlFor={`limit-${user.id}`} className="text-zinc-500">Daily limit (SMS parts)</label>
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
