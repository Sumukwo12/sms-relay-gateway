import type { Metadata } from "next";
import Link from "next/link";
import IntegrationDemo from "./components/integration-demo";
import PostmanUrl from "./components/postman-url";
import {
  APP_DOWNLOAD_URL,
  APP_SIZE,
  APP_VERSION,
  REPO_URL,
  SITE_DESCRIPTION,
  SITE_NAME,
  SITE_TITLE,
  SITE_URL,
} from "./lib/site";
import {
  BadgeCheck,
  Code2,
  Download,
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

const POSTMAN_ERRORS: [string, string][] = [
  [
    "401 unauthorized",
    "No key was sent, or it is mistyped or revoked. Set Authorization → Bearer Token with the full key (no spaces, no \"Bearer\" in the field).",
  ],
  ["403 account_pending", "A live key on an account that isn't approved yet. Use a test key until an admin approves you."],
  ["422 invalid_request", "A field is missing or wrong; the response's \"field\" names it."],
  ["429 rate_limited", "More than 3 codes to one number in an hour. Use another number or wait."],
  ["429 daily_limit_reached", "Your account's daily SMS limit is used up (test keys don't count)."],
];

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

export const metadata: Metadata = {
  alternates: { canonical: "/" },
  // Nested metadata objects replace the layout's, so repeat them in full
  openGraph: {
    type: "website",
    url: "/",
    siteName: SITE_NAME,
    title: SITE_TITLE,
    description: SITE_DESCRIPTION,
    locale: "en_KE",
  },
};

// Structured data so search engines understand what the site offers
const JSON_LD = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "WebSite",
      "@id": `${SITE_URL}/#website`,
      url: `${SITE_URL}/`,
      name: SITE_NAME,
      description: SITE_DESCRIPTION,
      inLanguage: "en",
    },
    {
      "@type": "WebApplication",
      name: SITE_NAME,
      url: `${SITE_URL}/`,
      description: SITE_DESCRIPTION,
      applicationCategory: "DeveloperApplication",
      operatingSystem: "Web, Android",
      offers: { "@type": "Offer", price: "0", priceCurrency: "KES" },
      featureList: [
        "Send OTP verification codes by SMS",
        "Send SMS notifications from your website",
        "Uses your own Android phone and SIM",
        "Delivery webhooks",
        "Test API keys",
      ],
    },
  ],
};

export default function Home() {
  return (
    <div className="flex flex-1 flex-col bg-zinc-50 font-sans text-zinc-900 dark:bg-black dark:text-zinc-100">
      <script
        type="application/ld+json"
        // Static data defined above, not user input
        dangerouslySetInnerHTML={{ __html: JSON.stringify(JSON_LD).replace(/</g, "\\u003c") }}
      />
      <header className="mx-auto flex w-full max-w-5xl items-center justify-between px-4 py-5 sm:px-8">
        <Link href="/" className="flex items-center gap-2 font-semibold">
          <span className="flex h-8 w-8 items-center justify-center rounded-lg bg-emerald-600 text-white">
            <MessageSquareText className="h-4 w-4" aria-hidden />
          </span>
          SMS Gateway
        </Link>
        <nav className="flex items-center gap-1 text-sm sm:gap-2">
          <a
            href={APP_DOWNLOAD_URL}
            download
            className="hidden items-center gap-1.5 rounded-lg px-3 py-2 font-medium hover:bg-zinc-100 sm:inline-flex dark:hover:bg-zinc-900"
          >
            <Download className="h-4 w-4" aria-hidden /> Get the app
          </a>
          <a
            href={REPO_URL}
            target="_blank"
            rel="noopener"
            className="hidden items-center gap-1.5 rounded-lg px-3 py-2 font-medium hover:bg-zinc-100 md:inline-flex dark:hover:bg-zinc-900"
          >
            <Code2 className="h-4 w-4" aria-hidden /> Source
          </a>
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
            <a
              href={APP_DOWNLOAD_URL}
              download
              className="inline-flex items-center gap-2 rounded-lg border border-zinc-300 px-5 py-2.5 font-semibold hover:bg-white dark:border-zinc-700 dark:hover:bg-zinc-900"
            >
              <Download className="h-4 w-4" aria-hidden /> Download the Android app
            </a>
          </div>
          <p className="mt-3 text-xs text-zinc-500">
            Already have an account? <Link href="/login" className="font-medium underline">Sign in</Link>
          </p>
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

        <section
          id="app"
          aria-labelledby="app-heading"
          className="mt-16 rounded-2xl border border-emerald-200 bg-emerald-50 p-6 sm:p-8 dark:border-emerald-900 dark:bg-emerald-950/50"
        >
          <div className="flex flex-col gap-6 md:flex-row md:items-center md:justify-between">
            <div className="max-w-xl">
              <h2 id="app-heading" className="text-2xl font-semibold tracking-tight">
                Get the SMS Relay app
              </h2>
              <p className="mt-2 text-sm text-zinc-700 dark:text-zinc-300">
                The Android app that turns your phone into the gateway. Install it, sign in with your account, and
                keep the phone charged and online.
              </p>
              <ul className="mt-3 list-disc space-y-1 pl-5 text-xs text-zinc-600 dark:text-zinc-400">
                <li>
                  Android may warn about installing an app from outside the Play Store. Allow it for your browser or
                  file manager.
                </li>
                <li>
                  If SMS permission is blocked (&ldquo;restricted setting&rdquo;): Settings → Apps → SMS Relay → ⋮ →
                  Allow restricted settings.
                </li>
                <li>On Xiaomi, Redmi and Samsung, turn on Autostart and set battery to No restrictions.</li>
              </ul>
            </div>
            <div className="shrink-0 text-center">
              <a
                href={APP_DOWNLOAD_URL}
                download
                className="inline-flex items-center gap-2 rounded-lg bg-emerald-600 px-6 py-3 font-semibold text-white hover:bg-emerald-700"
              >
                <Download className="h-5 w-5" aria-hidden /> Download APK
              </a>
              <p className="mt-2 text-xs text-zinc-500">
                Version {APP_VERSION} · {APP_SIZE} · Android 7+
              </p>
            </div>
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
                  OpenAPI specification
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

        <section className="mt-16" aria-labelledby="postman">
          <h2 id="postman" className="text-center text-2xl font-semibold tracking-tight">
            Test it with Postman
          </h2>
          <p className="mx-auto mt-2 max-w-2xl text-center text-sm text-zinc-600 dark:text-zinc-400">
            Try the API before writing any code. With a test key nothing is sent, and verification codes come back
            in the response.
          </p>

          <div className="mt-6 grid gap-4 lg:grid-cols-2">
            <div className="rounded-2xl border border-zinc-200 bg-white p-6 dark:border-zinc-800 dark:bg-zinc-950">
              <h3 className="font-semibold">Set up once</h3>
              <ol className="mt-3 list-decimal space-y-3 pl-5 text-sm text-zinc-600 dark:text-zinc-400">
                <li>
                  <strong className="text-zinc-800 dark:text-zinc-200">Get a test key.</strong> Sign in, open{" "}
                  <em>API keys</em>, create a key of type <em>Test</em> and copy the <code className="text-xs">sk_test_…</code>{" "}
                  value (it&apos;s shown once).
                </li>
                <li>
                  <strong className="text-zinc-800 dark:text-zinc-200">Import the API.</strong> In Postman choose{" "}
                  <em>Import → Link</em> and paste:
                  <PostmanUrl />
                </li>
                <li>
                  <strong className="text-zinc-800 dark:text-zinc-200">Add your key.</strong> Open the imported
                  collection&apos;s <em>Authorization</em> tab, choose <em>Bearer Token</em> and paste the key: just{" "}
                  <code className="text-xs">sk_test_…</code>, without the word &ldquo;Bearer&rdquo;. Requests inside
                  use <em>Inherit auth from parent</em>.
                </li>
              </ol>
              <p className="mt-4 text-xs text-zinc-500">
                No import? On any single request, open <em>Authorization → Bearer Token</em> and paste the key, then
                use <em>Body → raw → JSON</em>.
              </p>
            </div>

            <div className="rounded-2xl border border-zinc-200 bg-zinc-950 p-6 text-sm text-zinc-100 dark:border-zinc-800">
              <h3 className="font-semibold">Then run, in order</h3>
              <pre className="mt-3 overflow-x-auto font-mono text-xs leading-relaxed text-zinc-300">{`1  GET  /v1/status
   → 200  your account and whether your phone is online

2  POST /v1/otp/send      {"phone": "0712345678"}
   → 202  {"test_code": "483921", "message": {"status": "delivered", …}}

3  POST /v1/otp/verify    {"phone": "0712345678", "code": "483921"}
   → 200  {"verified": true}        (again → 422: codes work once)

4  POST /v1/messages      {"to": "0712345678", "body": "Hello"}
   → 202  then GET /v1/messages/{id} for its status`}</pre>
              <p className="mt-3 text-xs text-zinc-400">
                Works? Swap in a live key (<code>sk_…</code>) with your phone online: step 2 sends a real SMS and no
                longer returns <code>test_code</code>.
              </p>
            </div>
          </div>

          <div className="mt-4 overflow-x-auto rounded-2xl border border-zinc-200 bg-white dark:border-zinc-800 dark:bg-zinc-950">
            <table className="w-full min-w-[560px] text-left text-sm">
              <thead className="border-b border-zinc-200 text-xs uppercase text-zinc-500 dark:border-zinc-800">
                <tr>
                  <th className="px-5 py-2.5 font-medium">If you see</th>
                  <th className="px-5 py-2.5 font-medium">It means</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-zinc-100 text-zinc-700 dark:divide-zinc-800 dark:text-zinc-300">
                {POSTMAN_ERRORS.map(([code, meaning]) => (
                  <tr key={code}>
                    <td className="whitespace-nowrap px-5 py-2.5 font-mono text-xs">{code}</td>
                    <td className="px-5 py-2.5">{meaning}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      </main>

      <footer className="border-t border-zinc-200 dark:border-zinc-800">
        <div className="mx-auto grid w-full max-w-5xl gap-6 px-4 py-8 text-sm sm:grid-cols-3 sm:px-8">
          <div>
            <p className="font-semibold">{SITE_NAME}</p>
            <p className="mt-2 text-xs text-zinc-500">
              Your own SMS gateway for OTP codes and notifications, running on your Android phone.
            </p>
          </div>
          <nav aria-label="Product">
            <p className="text-xs font-semibold uppercase tracking-wide text-zinc-500">Product</p>
            <ul className="mt-2 space-y-1.5">
              <li><a href="#how" className="hover:underline">How the SMS gateway works</a></li>
              <li><a href="#simulation" className="hover:underline">Phone verification demo</a></li>
              <li><a href="#why" className="hover:underline">Why use your own phone</a></li>
            </ul>
          </nav>
          <nav aria-label="Developers">
            <p className="text-xs font-semibold uppercase tracking-wide text-zinc-500">Developers</p>
            <ul className="mt-2 space-y-1.5">
              <li><a href="#developers" className="hover:underline">API credentials and integration</a></li>
              <li><a href="#postman" className="hover:underline">Test the API with Postman</a></li>
              <li><a href="/openapi.json" className="hover:underline">OpenAPI specification (JSON)</a></li>
              <li><Link href="/register" className="hover:underline">Get a free API key</Link></li>
              <li><Link href="/login" className="hover:underline">Sign in to your dashboard</Link></li>
              <li><a href={APP_DOWNLOAD_URL} download className="hover:underline">Download the SMS Relay Android app</a></li>
              <li>
                <a href={REPO_URL} target="_blank" rel="noopener" className="hover:underline">
                  Source code on GitHub
                </a>
              </li>
            </ul>
          </nav>
        </div>
        <p className="pb-6 text-center text-xs text-zinc-500">
          SMS are sent from members&apos; own phones and SIMs. Follow your carrier&apos;s terms and local messaging rules.
        </p>
      </footer>
    </div>
  );
}
