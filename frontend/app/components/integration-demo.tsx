"use client";

import { useEffect, useRef, useState, type FormEvent } from "react";
import {
  ArrowRight,
  CircleCheck,
  Globe,
  MessageSquareText,
  RotateCcw,
  Server,
  Smartphone,
  UserRound,
} from "lucide-react";

/*
 * A simulated phone-verification integration, end to end. Nothing is sent:
 * each hop is replayed on a timer with the request and response a real
 * integration would see.
 */

const NODES = [
  { label: "Visitor's browser", icon: Globe },
  { label: "Your backend", icon: Server },
  { label: "SMS Gateway", icon: MessageSquareText },
  { label: "Your phone", icon: Smartphone },
  { label: "Visitor's phone", icon: UserRound },
] as const;

type Hop = {
  from: number;
  to: number;
  title: string;
  detail: string;
  /** Called when the hop finishes (e.g. the SMS arrives) */
  effect?: () => void;
};

type Phase = "idle" | "sending" | "awaiting-code" | "verifying" | "verified" | "rejected";

const STEP_MS = 1400;

export default function IntegrationDemo() {
  const [phone, setPhone] = useState("0712345678");
  const [typed, setTyped] = useState("");
  const [phase, setPhase] = useState<Phase>("idle");
  const [code, setCode] = useState("");
  const [smsVisible, setSmsVisible] = useState(false);
  const [active, setActive] = useState<Hop | null>(null);
  const [log, setLog] = useState<Hop[]>([]);
  const timers = useRef<ReturnType<typeof setTimeout>[]>([]);
  const logEnd = useRef<HTMLDivElement>(null);

  useEffect(() => () => timers.current.forEach(clearTimeout), []);

  useEffect(() => {
    logEnd.current?.scrollIntoView({ block: "nearest", behavior: "smooth" });
  }, [log]);

  function play(hops: Hop[], done: () => void) {
    timers.current.forEach(clearTimeout);
    timers.current = [];

    hops.forEach((hop, i) => {
      timers.current.push(
        setTimeout(() => {
          setActive(hop);
          setLog((l) => [...l, hop]);
          hop.effect?.();
        }, i * STEP_MS),
      );
    });

    timers.current.push(
      setTimeout(() => {
        setActive(null);
        done();
      }, hops.length * STEP_MS),
    );
  }

  function normalized() {
    const digits = phone.replace(/\D/g, "");
    if (phone.trim().startsWith("+")) return "+" + digits;
    if (digits.startsWith("0")) return "+254" + digits.slice(1);
    if (digits.startsWith("254")) return "+" + digits;
    return "+254" + digits;
  }

  function sendCode(e: FormEvent) {
    e.preventDefault();
    const otp = String(Math.floor(100000 + Math.random() * 900000));
    const to = normalized();
    setCode(otp);
    setTyped("");
    setSmsVisible(false);
    setLog([]);
    setPhase("sending");

    play(
      [
        {
          from: 0,
          to: 1,
          title: "The sign-up form posts the number to your own backend",
          detail: `POST https://your-site.example/signup/send-code\n{"phone": "${phone.trim()}"}`,
        },
        {
          from: 1,
          to: 2,
          title: "Your backend asks the gateway for a code (the API key stays on your server)",
          detail: `POST /v1/otp/send\nAuthorization: Bearer sk_••••••••\n{"phone": "${phone.trim()}", "template": "Your Acme code is {code}"}`,
        },
        {
          from: 2,
          to: 1,
          title: "The gateway queues the SMS and answers right away",
          detail: `202 Accepted\n{"success": true, "expires_in_seconds": 300,\n "message": {"id": "msg_3f9c…", "to": "${to}", "status": "queued"}}`,
        },
        {
          from: 2,
          to: 3,
          title: "The gateway hands the SMS to your phone over its secure connection",
          detail: `send_sms → {"id": "msg_3f9c…", "to": "${to}",\n            "body": "Your Acme code is ${otp}"}`,
        },
        {
          from: 3,
          to: 4,
          title: "Your phone sends the SMS from its own SIM",
          detail: `SMS to ${to}: "Your Acme code is ${otp}"`,
          effect: () => setSmsVisible(true),
        },
        {
          from: 2,
          to: 1,
          title: "Optional: a signed webhook tells your backend it was delivered",
          detail: `POST https://your-site.example/sms-events\nX-Signature: sha256=…\n{"event": "message.delivered", "message": {"id": "msg_3f9c…", "status": "delivered"}}`,
        },
      ],
      () => setPhase("awaiting-code"),
    );
  }

  function verify(e: FormEvent) {
    e.preventDefault();
    const ok = typed.trim() === code;
    const to = normalized();
    setPhase("verifying");

    play(
      [
        {
          from: 0,
          to: 1,
          title: "The visitor types the code; the form posts it to your backend",
          detail: `POST https://your-site.example/signup/verify\n{"phone": "${phone.trim()}", "code": "${typed.trim()}"}`,
        },
        {
          from: 1,
          to: 2,
          title: "Your backend asks the gateway to check it",
          detail: `POST /v1/otp/verify\nAuthorization: Bearer sk_••••••••\n{"phone": "${to}", "code": "${typed.trim()}"}`,
        },
        ok
          ? {
              from: 2,
              to: 1,
              title: "Correct: the code is used up, and your backend marks the number verified",
              detail: `200 OK\n{"success": true, "verified": true}`,
            }
          : {
              from: 2,
              to: 1,
              title: "Wrong code: your backend asks the visitor to try again",
              detail: `422 Unprocessable Entity\n{"success": false, "verified": false, "error": "invalid_code"}`,
            },
        {
          from: 1,
          to: 0,
          title: ok ? "The visitor sees “Phone number verified”" : "The visitor sees “That code is incorrect”",
          detail: ok ? `200 {"verified": true}` : `422 {"error": "invalid_code"}`,
        },
      ],
      () => setPhase(ok ? "verified" : "rejected"),
    );
  }

  function reset() {
    timers.current.forEach(clearTimeout);
    setPhase("idle");
    setActive(null);
    setLog([]);
    setSmsVisible(false);
    setTyped("");
    setCode("");
  }

  const busy = phase === "sending" || phase === "verifying";

  return (
    <div className="rounded-2xl border border-zinc-200 bg-white p-5 sm:p-6 dark:border-zinc-800 dark:bg-zinc-950">
      {/* Flow diagram */}
      <ol className="grid grid-cols-5 gap-1 sm:gap-2" aria-label="Where the request is">
        {NODES.map(({ label, icon: Icon }, i) => {
          const lit = active && (active.from === i || active.to === i);
          const sending = active?.from === i;
          return (
            <li key={label} className="flex flex-col items-center text-center">
              <span
                className={`flex h-10 w-10 items-center justify-center rounded-xl border transition-colors duration-300 sm:h-12 sm:w-12 ${
                  lit
                    ? sending
                      ? "border-amber-500 bg-amber-100 text-amber-800 dark:bg-amber-950 dark:text-amber-300"
                      : "border-emerald-600 bg-emerald-100 text-emerald-800 dark:bg-emerald-950 dark:text-emerald-300"
                    : "border-zinc-200 text-zinc-500 dark:border-zinc-800"
                }`}
              >
                <Icon className="h-5 w-5" aria-hidden />
              </span>
              <span className="mt-1.5 text-[10px] leading-tight text-zinc-600 sm:text-xs dark:text-zinc-400">{label}</span>
            </li>
          );
        })}
      </ol>

      <p className="mt-4 flex min-h-[2.5rem] items-center justify-center gap-2 text-center text-sm font-medium" aria-live="polite">
        {active ? (
          <>
            <span className="rounded bg-amber-100 px-1.5 py-0.5 text-xs text-amber-800 dark:bg-amber-950 dark:text-amber-300">
              {NODES[active.from].label}
            </span>
            <ArrowRight className="h-4 w-4 shrink-0 text-zinc-400 motion-safe:animate-pulse" aria-hidden />
            <span className="rounded bg-emerald-100 px-1.5 py-0.5 text-xs text-emerald-800 dark:bg-emerald-950 dark:text-emerald-300">
              {NODES[active.to].label}
            </span>
          </>
        ) : phase === "idle" ? (
          <span className="text-zinc-500">Press “Send code” to watch a verification travel through the system.</span>
        ) : phase === "verified" ? (
          <span className="inline-flex items-center gap-1.5 text-emerald-700 dark:text-emerald-400">
            <CircleCheck className="h-4 w-4" aria-hidden /> Phone number verified. That&apos;s the whole integration.
          </span>
        ) : phase === "rejected" ? (
          <span className="text-red-700 dark:text-red-400">Wrong code. Try again with the code on the phone.</span>
        ) : (
          <span className="text-zinc-500">The SMS has arrived. Type the code from the phone.</span>
        )}
      </p>

      <div className="mt-4 grid gap-4 lg:grid-cols-[1fr_15rem]">
        {/* Website side: the form, then the request log */}
        <div className="min-w-0 space-y-4">
          <div className="rounded-xl border border-zinc-200 p-4 dark:border-zinc-800">
            <p className="text-xs font-medium uppercase tracking-wide text-zinc-500">Your website&apos;s sign-up form</p>
            {phase === "idle" || phase === "sending" ? (
              <form onSubmit={sendCode} className="mt-3 flex flex-col gap-2 sm:flex-row">
                <label htmlFor="demo-phone" className="sr-only">Phone number</label>
                <input
                  id="demo-phone"
                  type="tel"
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  disabled={busy}
                  className="flex-1 rounded-lg border border-zinc-300 bg-transparent px-3 py-2 text-sm dark:border-zinc-700"
                />
                <button
                  type="submit"
                  disabled={busy || phone.replace(/\D/g, "").length < 9}
                  className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white transition hover:bg-emerald-700 disabled:opacity-50"
                >
                  {busy ? "Sending…" : "Send code"}
                </button>
              </form>
            ) : (
              <form onSubmit={verify} className="mt-3 flex flex-col gap-2 sm:flex-row">
                <label htmlFor="demo-code" className="sr-only">Verification code</label>
                <input
                  id="demo-code"
                  inputMode="numeric"
                  maxLength={6}
                  placeholder="6-digit code"
                  value={typed}
                  onChange={(e) => setTyped(e.target.value.replace(/\D/g, ""))}
                  disabled={busy || phase === "verified"}
                  className="flex-1 rounded-lg border border-zinc-300 bg-transparent px-3 py-2 font-mono text-sm tracking-widest dark:border-zinc-700"
                />
                {phase !== "verified" && (
                  <button
                    type="button"
                    onClick={() => setTyped(code)}
                    disabled={busy}
                    className="rounded-lg border border-zinc-300 px-3 py-2 text-sm font-medium hover:bg-zinc-50 disabled:opacity-50 dark:border-zinc-700 dark:hover:bg-zinc-900"
                  >
                    Use code from SMS
                  </button>
                )}
                {phase !== "verified" ? (
                  <button
                    type="submit"
                    disabled={busy || typed.length !== 6}
                    className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white transition hover:bg-emerald-700 disabled:opacity-50"
                  >
                    {busy ? "Checking…" : "Verify"}
                  </button>
                ) : (
                  <button
                    type="button"
                    onClick={reset}
                    className="inline-flex items-center justify-center gap-1.5 rounded-lg border border-zinc-300 px-4 py-2 text-sm font-medium hover:bg-zinc-50 dark:border-zinc-700 dark:hover:bg-zinc-900"
                  >
                    <RotateCcw className="h-4 w-4" aria-hidden /> Run again
                  </button>
                )}
              </form>
            )}
          </div>

          <div className="rounded-xl bg-zinc-950 p-4 text-zinc-100 dark:border dark:border-zinc-800">
            <div className="flex items-center justify-between">
              <p className="text-xs font-medium uppercase tracking-wide text-zinc-400">What happens, step by step</p>
              {log.length > 0 && !busy && (
                <button type="button" onClick={reset} className="text-xs text-zinc-400 hover:text-zinc-200">
                  Reset
                </button>
              )}
            </div>
            <div className="mt-3 max-h-80 space-y-3 overflow-y-auto pr-1">
              {log.length === 0 && (
                <p className="font-mono text-xs text-zinc-500">Requests and responses appear here.</p>
              )}
              {log.map((hop, i) => (
                <div key={i} className="motion-safe:animate-[fadeIn_0.3s_ease-out]">
                  <p className="text-xs text-amber-300">
                    {i + 1}. {hop.title}
                  </p>
                  <pre className="mt-1 overflow-x-auto whitespace-pre-wrap break-all font-mono text-[11px] leading-relaxed text-zinc-300">
                    {hop.detail}
                  </pre>
                </div>
              ))}
              <div ref={logEnd} />
            </div>
          </div>
        </div>

        {/* The visitor's phone */}
        <div className="mx-auto w-full max-w-[15rem]">
          <div className="rounded-[2rem] border-4 border-zinc-800 bg-zinc-100 p-3 shadow-sm dark:border-zinc-700 dark:bg-zinc-900">
            <div className="mx-auto mb-3 h-1.5 w-16 rounded-full bg-zinc-300 dark:bg-zinc-700" />
            <p className="text-center text-[11px] text-zinc-500">Visitor&apos;s phone</p>
            <div className="mt-2 flex h-52 flex-col justify-end gap-2 rounded-xl bg-white p-2 dark:bg-zinc-950">
              {smsVisible ? (
                <div className="motion-safe:animate-[fadeIn_0.4s_ease-out]">
                  <p className="text-[10px] text-zinc-500">From: your phone number</p>
                  <div className="mt-1 rounded-2xl rounded-bl-sm bg-zinc-100 px-3 py-2 text-sm dark:bg-zinc-800">
                    Your Acme code is <span className="font-mono font-semibold">{code}</span>
                  </div>
                </div>
              ) : (
                <p className="text-center text-xs text-zinc-400">No messages yet</p>
              )}
            </div>
          </div>
        </div>
      </div>

      <p className="mt-4 text-center text-xs text-zinc-500">
        This is a simulation: nothing is sent. With a test key (<code>sk_test_…</code>) you can run the same calls for
        real without sending SMS.
      </p>
    </div>
  );
}
