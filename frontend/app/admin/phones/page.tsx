"use client";

import { getAdminDevices } from "../../lib/account";
import { useLoad } from "../../lib/use-load";
import { Alert, Card, OnlineDot, PageHeader, Spinner, timeAgo } from "../../components/ui";

export default function AdminPhonesPage() {
  const { data, error } = useLoad(getAdminDevices, 10_000);
  const devices = data?.devices ?? [];
  const online = devices.filter((d) => d.online).length;

  return (
    <>
      <PageHeader title="All phones" description="Every phone signed in to the gateway, with its owner and health." />

      {error && !data && <Alert>{error.message}</Alert>}
      {!data && !error && <Spinner />}

      {data && (
        <Card title={`${online} of ${devices.length} online`}>
          {devices.length === 0 ? (
            <p className="text-sm text-zinc-500">No phones linked yet.</p>
          ) : (
            <div className="-mx-5 overflow-x-auto sm:-mx-6">
              <table className="w-full min-w-[640px] text-left text-sm">
                <thead className="border-b border-zinc-200 text-xs uppercase text-zinc-500 dark:border-zinc-800">
                  <tr>
                    <th className="px-5 py-2 font-medium sm:px-6">Phone</th>
                    <th className="px-2 py-2 font-medium">Owner</th>
                    <th className="px-2 py-2 font-medium">Status</th>
                    <th className="px-2 py-2 font-medium">Battery / signal</th>
                    <th className="px-5 py-2 font-medium sm:px-6">App</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-zinc-100 dark:divide-zinc-800">
                  {devices.map((d) => (
                    <tr key={d.id}>
                      <td className="px-5 py-2.5 sm:px-6">
                        <p className="font-medium">{d.name}</p>
                        <p className="text-xs text-zinc-500">{d.model ?? "Unknown model"} · ID {d.id}</p>
                      </td>
                      <td className="px-2 py-2.5 text-xs">{d.owner?.email}</td>
                      <td className="px-2 py-2.5">
                        <OnlineDot online={d.online} />
                        {!d.online && <p className="text-xs text-zinc-500">seen {timeAgo(d.last_seen_at)}</p>}
                      </td>
                      <td className="px-2 py-2.5 text-xs text-zinc-500">
                        {d.online
                          ? [d.battery != null && `${d.battery}%${d.charging ? " ⚡" : ""}`, d.signal != null && `signal ${d.signal}/4`]
                              .filter(Boolean)
                              .join(" · ") || "—"
                          : "—"}
                      </td>
                      <td className="px-5 py-2.5 text-xs text-zinc-500 sm:px-6">{d.app_version ?? "—"}</td>
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
