"use client";

import Link from "next/link";
import { ArrowRight, CircleCheck, Circle } from "lucide-react";
import { getOverview } from "../lib/account";
import { useLoad } from "../lib/use-load";
import { Alert, Card, OnlineDot, PageHeader, Spinner, timeAgo } from "../components/ui";
import { useSession } from "./session";

export default function OverviewPage() {
  const { user } = useSession();
  const { data, error } = useLoad(getOverview, 15_000);

  if (error && !data) return <Alert>{error.message}</Alert>;
  if (!data) return <Spinner />;

  const { usage, devices } = data;
  const percent = Math.min(100, Math.round((usage.sent_last_24h / Math.max(usage.daily_limit, 1)) * 100));

  const steps = [
    { done: devices.length > 0, label: "Install the SMS Relay app and sign in on your phone", href: "/dashboard/phones" },
    { done: data.api_keys > 0, label: "Create an API key for your system", href: "/dashboard/keys" },
    { done: user.status === "approved", label: "Get approved by an administrator", href: null },
    { done: usage.sent_last_24h > 0, label: "Send a test SMS from the console", href: "/dashboard/console" },
  ];

  return (
    <>
      <PageHeader
        title={`Hello${user.name ? `, ${user.name}` : ""}`}
        description="Your own SMS gateway: your systems call the API, your phone sends the SMS."
      />

      <div className="grid gap-4 sm:grid-cols-3">
        <Card>
          <p className="text-sm text-zinc-500">Gateway</p>
          <p className="mt-2 text-lg font-semibold">
            {data.gateway_online ? "Ready to send" : "No phone online"}
          </p>
          <div className="mt-1">
            <OnlineDot online={data.gateway_online} />
          </div>
        </Card>
        <Card>
          <p className="text-sm text-zinc-500">Sent in the last 24h</p>
          <p className="mt-2 text-lg font-semibold">
            {usage.sent_last_24h} <span className="text-sm font-normal text-zinc-500">/ {usage.daily_limit} SMS parts</span>
          </p>
          <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-zinc-100 dark:bg-zinc-800">
            <div
              className={`h-full rounded-full ${percent >= 90 ? "bg-amber-500" : "bg-emerald-500"}`}
              style={{ width: `${percent}%` }}
            />
          </div>
        </Card>
        <Card>
          <p className="text-sm text-zinc-500">Waiting to send</p>
          <p className="mt-2 text-lg font-semibold">{usage.queued}</p>
          <p className="mt-1 text-xs text-zinc-500">
            {usage.queued > 0 && !data.gateway_online
              ? "They go out when your phone reconnects."
              : "Queued messages"}
          </p>
        </Card>
      </div>

      <div className="mt-4 grid gap-4 lg:grid-cols-2">
        <Card title="Getting started">
          <ol className="space-y-3">
            {steps.map(({ done, label, href }) => (
              <li key={label} className="flex items-start gap-3 text-sm">
                {done ? (
                  <CircleCheck className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" aria-label="Done" />
                ) : (
                  <Circle className="mt-0.5 h-4 w-4 shrink-0 text-zinc-400" aria-label="To do" />
                )}
                {href && !done ? (
                  <Link href={href} className="font-medium text-emerald-700 hover:underline dark:text-emerald-400">
                    {label}
                  </Link>
                ) : (
                  <span className={done ? "text-zinc-500 line-through" : ""}>{label}</span>
                )}
              </li>
            ))}
          </ol>
        </Card>

        <Card
          title="Your phones"
          action={
            <Link href="/dashboard/phones" className="inline-flex items-center gap-1 text-sm font-medium text-emerald-700 dark:text-emerald-400">
              Manage <ArrowRight className="h-4 w-4" aria-hidden />
            </Link>
          }
        >
          {devices.length === 0 ? (
            <p className="text-sm text-zinc-500">No phone linked yet.</p>
          ) : (
            <ul className="divide-y divide-zinc-100 dark:divide-zinc-800">
              {devices.map((d) => (
                <li key={d.id} className="flex items-center justify-between py-2.5 text-sm">
                  <div>
                    <p className="font-medium">{d.name}</p>
                    <p className="text-xs text-zinc-500">
                      {d.online
                        ? [d.battery != null && `Battery ${d.battery}%`, d.model].filter(Boolean).join(" · ") || d.model
                        : `Last seen ${timeAgo(d.last_seen_at)}`}
                    </p>
                  </div>
                  <OnlineDot online={d.online} />
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>
    </>
  );
}
