"use client";

import { RotateCw } from "lucide-react";
import { getMessages, type MessageStatus } from "../../lib/account";
import { useLoad } from "../../lib/use-load";
import { Alert, Badge, Button, Card, PageHeader, Spinner, timeAgo } from "../../components/ui";

const STATUS_TONE: Record<MessageStatus, "neutral" | "green" | "amber" | "red" | "blue"> = {
  queued: "amber",
  sending: "blue",
  sent: "green",
  delivered: "green",
  failed: "red",
};

export default function MessagesPage() {
  const { data, error, reload } = useLoad(getMessages, 10_000);

  return (
    <>
      <PageHeader
        title="Messages"
        description="Your latest 100 messages. Message text isn't stored once a message is done."
      />

      {error && !data && <Alert>{error.message}</Alert>}
      {!data && !error && <Spinner />}

      {data && (
        <Card
          action={
            <Button variant="secondary" onClick={reload} className="px-3 py-1.5">
              <RotateCw className="h-4 w-4" aria-hidden /> Refresh
            </Button>
          }
          title={`${data.messages.length} message${data.messages.length === 1 ? "" : "s"}`}
        >
          {data.messages.length === 0 ? (
            <p className="text-sm text-zinc-500">Nothing sent yet. Try the test console.</p>
          ) : (
            <div className="-mx-5 overflow-x-auto sm:-mx-6">
              <table className="w-full min-w-[640px] text-left text-sm">
                <thead className="border-b border-zinc-200 text-xs uppercase text-zinc-500 dark:border-zinc-800">
                  <tr>
                    <th className="px-5 py-2 font-medium sm:px-6">To</th>
                    <th className="px-2 py-2 font-medium">Type</th>
                    <th className="px-2 py-2 font-medium">Status</th>
                    <th className="px-2 py-2 font-medium">Reference</th>
                    <th className="px-5 py-2 font-medium sm:px-6">Created</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-zinc-100 dark:divide-zinc-800">
                  {data.messages.map((m) => (
                    <tr key={m.id}>
                      <td className="px-5 py-2.5 sm:px-6">
                        <p className="font-mono text-xs">{m.to}</p>
                        <p className="text-xs text-zinc-500">{m.id}</p>
                      </td>
                      <td className="px-2 py-2.5 text-xs">{m.kind === "otp" ? "Code" : "SMS"}{m.segments > 1 ? ` · ${m.segments} parts` : ""}</td>
                      <td className="px-2 py-2.5">
                        <Badge tone={STATUS_TONE[m.status]}>{m.status}</Badge>
                        {m.error && <p className="mt-1 max-w-[16rem] text-xs text-red-600 dark:text-red-400">{m.error}</p>}
                      </td>
                      <td className="px-2 py-2.5 text-xs text-zinc-500">{m.reference ?? "—"}</td>
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
