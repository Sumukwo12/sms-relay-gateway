import Link from "next/link";
import { Code2, KeyRound, MessageSquareText, ShieldCheck, Smartphone, Wallet } from "lucide-react";

const STEPS = [
  {
    icon: Smartphone,
    title: "Link your phone",
    text: "Install the SMS Relay app on any Android phone with a SIM and sign in. It becomes your gateway.",
  },
  {
    icon: KeyRound,
    title: "Get an API key",
    text: "Create a key in the dashboard for each system that needs to send SMS.",
  },
  {
    icon: Code2,
    title: "Integrate",
    text: "Call one HTTP endpoint to send verification codes or any SMS, with delivery webhooks.",
  },
];

const FEATURES = [
  { icon: Wallet, title: "Pay your SIM bundle, not per message", text: "SMS go out from your own number at your carrier's rates." },
  { icon: ShieldCheck, title: "Verification codes built in", text: "The gateway generates, sends, rate-limits and checks one-time codes for you." },
  { icon: MessageSquareText, title: "Queued and retried", text: "If your phone is offline, messages wait and go out when it reconnects." },
];

export default function Home() {
  return (
    <div className="flex flex-1 flex-col bg-zinc-50 font-sans text-zinc-900 dark:bg-black dark:text-zinc-100">
      <header className="mx-auto flex w-full max-w-5xl items-center justify-between px-4 py-5 sm:px-8">
        <Link href="/" className="flex items-center gap-2 font-semibold">
          <span className="flex h-8 w-8 items-center justify-center rounded-lg bg-emerald-600 text-white">
            <MessageSquareText className="h-4 w-4" aria-hidden />
          </span>
          SMS Gateway
        </Link>
        <nav className="flex items-center gap-2 text-sm">
          <Link href="/login" className="rounded-lg px-3 py-2 font-medium hover:bg-zinc-100 dark:hover:bg-zinc-900">
            Sign in
          </Link>
          <Link href="/register" className="rounded-lg bg-emerald-600 px-3 py-2 font-semibold text-white hover:bg-emerald-700">
            Get started
          </Link>
        </nav>
      </header>

      <main className="mx-auto w-full max-w-5xl flex-1 px-4 pb-16 sm:px-8">
        <section className="py-14 text-center sm:py-20">
          <h1 className="mx-auto max-w-2xl text-4xl font-semibold tracking-tight sm:text-5xl">
            Your own SMS gateway, on your own phone
          </h1>
          <p className="mx-auto mt-4 max-w-xl text-lg text-zinc-600 dark:text-zinc-400">
            Send verification codes and notifications from your systems through an Android phone
            and SIM you already have, instead of paying an SMS provider per message.
          </p>
          <div className="mt-8 flex flex-wrap justify-center gap-3">
            <Link href="/register" className="rounded-lg bg-emerald-600 px-5 py-2.5 font-semibold text-white hover:bg-emerald-700">
              Create a free account
            </Link>
            <Link href="/demo" className="rounded-lg border border-zinc-300 px-5 py-2.5 font-semibold hover:bg-white dark:border-zinc-700 dark:hover:bg-zinc-900">
              Try the verification demo
            </Link>
          </div>
        </section>

        <section className="grid gap-4 sm:grid-cols-3">
          {STEPS.map(({ icon: Icon, title, text }, i) => (
            <div key={title} className="rounded-2xl border border-zinc-200 bg-white p-6 dark:border-zinc-800 dark:bg-zinc-950">
              <div className="flex items-center gap-3">
                <span className="flex h-9 w-9 items-center justify-center rounded-lg bg-emerald-50 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400">
                  <Icon className="h-5 w-5" aria-hidden />
                </span>
                <span className="text-xs font-medium text-zinc-500">Step {i + 1}</span>
              </div>
              <h2 className="mt-4 font-semibold">{title}</h2>
              <p className="mt-1 text-sm text-zinc-600 dark:text-zinc-400">{text}</p>
            </div>
          ))}
        </section>

        <section className="mt-12 grid gap-6 sm:grid-cols-3">
          {FEATURES.map(({ icon: Icon, title, text }) => (
            <div key={title} className="flex gap-3">
              <Icon className="mt-0.5 h-5 w-5 shrink-0 text-emerald-600" aria-hidden />
              <div>
                <h3 className="text-sm font-semibold">{title}</h3>
                <p className="mt-1 text-sm text-zinc-600 dark:text-zinc-400">{text}</p>
              </div>
            </div>
          ))}
        </section>

        <section className="mt-12 rounded-2xl border border-zinc-200 bg-zinc-950 p-6 text-sm text-zinc-100 dark:border-zinc-800">
          <p className="mb-3 text-xs uppercase tracking-wide text-zinc-400">Send a verification code</p>
          <pre className="overflow-x-auto font-mono text-xs leading-relaxed">{`curl -X POST https://<this-site>/v1/otp/send \\
  -H "Authorization: Bearer sk_..." \\
  -H "Content-Type: application/json" \\
  -d '{"phone": "+254712345678"}'`}</pre>
        </section>
      </main>

      <footer className="py-6 text-center text-xs text-zinc-500">
        SMS are sent from members&apos; own phones and SIMs. Follow your carrier&apos;s terms and local messaging rules.
      </footer>
    </div>
  );
}
