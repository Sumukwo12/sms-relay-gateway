"use client";

import { useState } from "react";
import { getAdminMessages, type MessageStatus } from "../../lib/account";
import { useLoad } from "../../lib/use-load";
import { Alert, Badge, Card, PageHeader, Spinner, timeAgo } from "../../components/ui";

const STATUS_TONE: Record<MessageStatus, "neutral" | "green" | "amber" | "red" | "blue"> = {
  queued: "amber",
  sending: "blue",
  sent: "green",
  delivered: "green",
  failed: "red",
};

export default function AdminMessagesPage() {
  const { data, error } = useLoad(getAdminMessages, 10_000);
  const [status, setStatus] = useState<MessageStatus | "all">("all");
  const list = (data?.messages ?? []).filter((m) => status === "all" || m.status === status);

  return (
    <>
      <PageHeader
        title="All messages"
        description="The latest 200 messages across every account. Message text isn't stored once a message is done."
      />

      {error && !data && <Alert>{error.message}</Alert>}
      {!data && !error && <Spinner />}

      {data && (
        <Card
          title={`${list.length} message${list.length === 1 ? "" : "s"}`}
          action={
            <select
              value={status}
              onChange={(e) => setStatus(e.target.value as MessageStatus | "all")}
              aria-label="Filter by status"
              className="rounded-lg border border-zinc-300 bg-transparent px-2 py-1 text-sm dark:border-zinc-700"
            >
              <option value="all">All statuses</option>
              <option value="queued">Queued</option>
              <option value="sending">Sending</option>
              <option value="sent">Sent</option>
              <option value="delivered">Delivered</option>
              <option value="failed">Failed</option>
            </select>
          }
        >
          {list.length === 0 ? (
            <p className="text-sm text-zinc-500">No messages.</p>
          ) : (
            <div className="-mx-5 overflow-x-auto sm:-mx-6">
              <table className="w-full min-w-[720px] text-left text-sm">
                <thead className="border-b border-zinc-200 text-xs uppercase text-zinc-500 dark:border-zinc-800">
                  <tr>
                    <th className="px-5 py-2 font-medium sm:px-6">Owner</th>
                    <th className="px-2 py-2 font-medium">To</th>
                    <th className="px-2 py-2 font-medium">Type</th>
                    <th className="px-2 py-2 font-medium">Status</th>
                    <th className="px-5 py-2 font-medium sm:px-6">Created</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-zinc-100 dark:divide-zinc-800">
                  {list.map((m) => (
                    <tr key={m.id}>
                      <td className="px-5 py-2.5 text-xs sm:px-6">{m.owner}</td>
                      <td className="px-2 py-2.5">
                        <p className="font-mono text-xs">{m.to}</p>
                        <p className="text-xs text-zinc-500">{m.id}</p>
                      </td>
                      <td className="px-2 py-2.5 text-xs">{m.kind === "otp" ? "Code" : "SMS"}</td>
                      <td className="px-2 py-2.5">
                        <Badge tone={STATUS_TONE[m.status]}>{m.status}</Badge>{m.test && <span className="ml-1"><Badge tone="blue">test</Badge></span>}
                        {m.error && <p className="mt-1 max-w-[16rem] text-xs text-red-600 dark:text-red-400">{m.error}</p>}
                      </td>
                      <td className="px-5 py-2.5 text-xs text-zinc-500 sm:px-6" title={m.created_at}>
                        {timeAgo(m.created_at)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      )}
    </>
  );
}
