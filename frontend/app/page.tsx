import Link from "next/link";
import IntegrationDemo from "./components/integration-demo";
import {
  BadgeCheck,
  Code2,
  KeyRound,
  FlaskConical,
  ListChecks,
  Lock,
  MessageSquareText,
  ShieldCheck,
  Smartphone,
  UserPlus,
  Wallet,
  Webhook,
} from "lucide-react";

const CREDENTIALS = [
  {
    icon: KeyRound,
    name: "Live API key",
    sample: "sk_…",
    text: "Sends real SMS and verification codes through your own phone. Created and revoked in the dashboard.",
  },
  {
    icon: FlaskConical,
    name: "Test API key",
    sample: "sk_test_…",
    text: "For building and testing: nothing is sent, nothing counts against your limit, and OTP codes come back in the response.",
  },
  {
    icon: Webhook,
    name: "Webhook secret",
    sample: "whsec_…",
    text: "Lets your web app check that delivery and phone-status events really came from the gateway.",
  },
];

const STEPS = [
  {
    icon: UserPlus,
    title: "Create an account",
    text: "Sign up on this website or in the SMS Relay app. An administrator reviews and approves new accounts.",
  },
  {
    icon: Smartphone,
    title: "Link your phone",
    text: "Install the SMS Relay app on an Android phone with a SIM card and sign in. That phone becomes your SMS gateway.",
  },
  {
    icon: KeyRound,
    title: "Get an API key",
    text: "Create a key in your dashboard for each website or system that needs to send SMS.",
  },
  {
    icon: Code2,
    title: "Integrate and send",
    text: "Your system calls one HTTP endpoint; the message goes out from your phone. Test everything first in the dashboard console.",
  },
];

const FEATURES = [
  {
    icon: Wallet,
    title: "No per-message fees",
    text: "Bulk SMS providers charge for every message. Here SMS go out from your own number at your SIM bundle's rates.",
  },
  {
    icon: ShieldCheck,
    title: "Verification codes built in",
    text: "The gateway generates one-time codes, texts them, rate-limits abuse and checks what the user types in.",
  },
  {
    icon: MessageSquareText,
    title: "Notifications too",
    text: "Send any text (order updates, reminders, alerts) and follow its status: queued, sent, delivered or failed.",
  },
  {
    icon: ListChecks,
    title: "Reliable",
    text: "If your phone is offline, messages wait in a queue and go out when it reconnects. Delivery webhooks tell your system.",
  },
  {
    icon: BadgeCheck,
    title: "Your numbers, your control",
    text: "Each account sends only through its own phones, with its own API keys, limits and message history.",
  },
  {
    icon: Smartphone,
    title: "Several phones",
    text: "Link more than one phone (or SIM) and choose which one sends, or let the gateway use the most recent.",
  },
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
            Create account
          </Link>
        </nav>
      </header>

      <main className="mx-auto w-full max-w-5xl flex-1 px-4 pb-16 sm:px-8">
        <section className="py-14 text-center sm:py-20">
          <p className="text-sm font-semibold text-amber-600 dark:text-amber-400">A low-cost alternative to SMS providers</p>
          <h1 className="mx-auto mt-3 max-w-2xl text-4xl font-semibold tracking-tight sm:text-5xl">
            Turn your Android phone into your own SMS gateway
          </h1>
          <p className="mx-auto mt-4 max-w-2xl text-lg text-zinc-600 dark:text-zinc-400">
            Send verification codes (OTP) and notifications from your website or app through a phone
            and SIM you already own, instead of paying a provider like Twilio for every message.
          </p>
          <div className="mt-8 flex flex-wrap justify-center gap-3">
            <Link href="/register" className="rounded-lg bg-emerald-600 px-5 py-2.5 font-semibold text-white hover:bg-emerald-700">
              Create an account
            </Link>
            <Link href="/login" className="rounded-lg border border-zinc-300 px-5 py-2.5 font-semibold hover:bg-white dark:border-zinc-700 dark:hover:bg-zinc-900">
              Sign in
            </Link>
          </div>
          <a href="#simulation" className="mt-4 inline-block text-sm font-medium text-amber-700 underline-offset-4 hover:underline dark:text-amber-400">
            Watch the demo ↓
          </a>
        </section>

        <section aria-labelledby="how">
          <h2 id="how" className="text-center text-2xl font-semibold tracking-tight">How it works</h2>
          <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            {STEPS.map(({ icon: Icon, title, text }, i) => (
              <div key={title} className="rounded-2xl border border-zinc-200 bg-white p-6 dark:border-zinc-800 dark:bg-zinc-950">
                <div className="flex items-center gap-3">
                  <span className="flex h-9 w-9 items-center justify-center rounded-lg bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400">
                    <Icon className="h-5 w-5" aria-hidden />
                  </span>
                  <span className="text-xs font-medium text-zinc-500">Step {i + 1}</span>
                </div>
                <h3 className="mt-4 font-semibold">{title}</h3>
                <p className="mt-1 text-sm text-zinc-600 dark:text-zinc-400">{text}</p>
              </div>
            ))}
          </div>
        </section>

        <section className="mt-16" aria-labelledby="why">
          <h2 id="why" className="text-center text-2xl font-semibold tracking-tight">Why use it</h2>
          <div className="mt-6 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
            {FEATURES.map(({ icon: Icon, title, text }) => (
              <div key={title} className="flex gap-3">
                <Icon className="mt-0.5 h-5 w-5 shrink-0 text-emerald-600" aria-hidden />
                <div>
                  <h3 className="text-sm font-semibold">{title}</h3>
                  <p className="mt-1 text-sm text-zinc-600 dark:text-zinc-400">{text}</p>
                </div>
              </div>
            ))}
          </div>
        </section>

        <section className="mt-16 grid gap-6 lg:grid-cols-2">
          <div className="rounded-2xl border border-zinc-200 bg-white p-6 dark:border-zinc-800 dark:bg-zinc-950">
            <h2 className="font-semibold">What you need</h2>
            <ul className="mt-3 list-disc space-y-1.5 pl-5 text-sm text-zinc-600 dark:text-zinc-400">
              <li>An Android phone with a SIM card and an SMS bundle or airtime</li>
              <li>The phone online (Wi-Fi or mobile data) and charging while it works as your gateway</li>
              <li>The SMS Relay app, signed in with your account</li>
              <li>A website or system that can make HTTP requests</li>
            </ul>
          </div>
          <div className="rounded-2xl border border-zinc-200 bg-zinc-950 p-6 text-sm text-zinc-100 dark:border-zinc-800">
            <p className="mb-3 text-xs uppercase tracking-wide text-zinc-400">Send a verification code from your system</p>
            <pre className="overflow-x-auto font-mono text-xs leading-relaxed">{`curl -X POST https://<this-site>/v1/otp/send \\
  -H "Authorization: Bearer sk_..." \\
  -H "Content-Type: application/json" \\
  -d '{"phone": "+254712345678"}'`}</pre>
            <p className="mt-3 text-xs text-zinc-400">Full documentation is in your dashboard after signing in.</p>
          </div>
        </section>

        <section className="mt-16" aria-labelledby="simulation">
          <h2 id="simulation" className="text-center text-2xl font-semibold tracking-tight">
            See it in action
          </h2>
          <p className="mx-auto mt-2 mb-6 max-w-2xl text-center text-sm text-zinc-600 dark:text-zinc-400">
            A simulated phone verification on a website, end to end. Watch each request travel from the visitor&apos;s
            browser to your phone and back, with the exact API calls your website would make.
          </p>
          <IntegrationDemo />
        </section>

        <section className="mt-16" aria-labelledby="developers">
          <h2 id="developers" className="text-center text-2xl font-semibold tracking-tight">
            For developers: connect your website
          </h2>
          <p className="mx-auto mt-2 max-w-2xl text-center text-sm text-zinc-600 dark:text-zinc-400">
            Every account gets its own credentials in the dashboard. No waiting for anyone to hand out keys.
          </p>

          <div className="mt-6 grid gap-4 md:grid-cols-3">
            {CREDENTIALS.map(({ icon: Icon, name, sample, text }) => (
              <div key={name} className="rounded-2xl border border-zinc-200 bg-white p-5 dark:border-zinc-800 dark:bg-zinc-950">
                <div className="flex items-center gap-2">
                  <Icon className="h-5 w-5 text-emerald-600" aria-hidden />
                  <h3 className="font-semibold">{name}</h3>
                </div>
                <code className="mt-2 inline-block rounded bg-zinc-100 px-1.5 py-0.5 font-mono text-xs dark:bg-zinc-900">
                  {sample}
                </code>
                <p className="mt-2 text-sm text-zinc-600 dark:text-zinc-400">{text}</p>
              </div>
            ))}
          </div>

          <div className="mt-4 grid gap-4 lg:grid-cols-2">
            <div className="rounded-2xl border border-zinc-200 bg-white p-6 dark:border-zinc-800 dark:bg-zinc-950">
              <h3 className="font-semibold">Integrate in four steps</h3>
              <ol className="mt-3 list-decimal space-y-2 pl-5 text-sm text-zinc-600 dark:text-zinc-400">
                <li>Create an account. A test key works straight away, even before approval.</li>
                <li>
                  Create a key and put it in your web app&apos;s <strong>server-side</strong> config, e.g.{" "}
                  <code className="text-xs">SMS_GATEWAY_KEY=sk_test_…</code> in <code className="text-xs">.env</code>.
                </li>
                <li>
                  From your backend, call <code className="text-xs">POST /v1/otp/send</code> when a user enters their
                  number, and <code className="text-xs">POST /v1/otp/verify</code> when they type the code.
                </li>
                <li>When it works, swap in a live key: the same calls now send real SMS from your phone.</li>
              </ol>
              <p className="mt-4 text-xs text-zinc-500">
                Examples in curl, PHP, Node.js and Python are in the dashboard; the full API is at{" "}
                <a href="/openapi.json" className="font-medium text-emerald-700 underline dark:text-emerald-400">
                  /openapi.json
                </a>{" "}
                (import it into Postman).
              </p>
            </div>

            <div className="rounded-2xl border border-amber-300 bg-amber-50 p-6 dark:border-amber-800 dark:bg-amber-950/50">
              <div className="flex items-center gap-2">
                <Lock className="h-5 w-5 text-amber-700 dark:text-amber-400" aria-hidden />
                <h3 className="font-semibold text-amber-900 dark:text-amber-200">Keep API keys on your server</h3>
              </div>
              <p className="mt-3 text-sm text-amber-900 dark:text-amber-200">
                Never put an API key in browser JavaScript, a mobile app or a public repository. Anyone who sees it
                can send SMS through your phone and use up your airtime.
              </p>
              <p className="mt-2 text-sm text-amber-900 dark:text-amber-200">
                Your web page calls <em>your own</em> backend; your backend calls the gateway with the key. If a key
                leaks, revoke it in the dashboard and create a new one.
              </p>
              <pre className="mt-4 overflow-x-auto rounded-lg bg-white/70 p-3 font-mono text-xs text-amber-950 dark:bg-black/30 dark:text-amber-100">{`Browser  ──►  your backend  ──►  SMS Gateway  ──►  your phone  ──►  SMS
              (holds sk_…)`}</pre>
            </div>
          </div>
        </section>
      </main>

      <footer className="py-6 text-center text-xs text-zinc-500">
        SMS are sent from members&apos; own phones and SIMs. Follow your carrier&apos;s terms and local messaging rules.
      </footer>
    </div>
  );
}
