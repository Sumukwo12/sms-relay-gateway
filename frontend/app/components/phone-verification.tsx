"use client";

import {
  useEffect,
  useRef,
  useState,
  type FormEvent,
  type ReactNode,
} from "react";
import {
  ArrowLeft,
  CircleAlert,
  CircleCheck,
  LoaderCircle,
  MessageSquareText,
  RotateCw,
  ShieldCheck,
  Smartphone,
} from "lucide-react";
import {
  getModemStatus,
  sendCode,
  verifyCode,
  type ApiError,
  type ModemStatus,
} from "../lib/api";

const CODE_LENGTH = 6;
const RESEND_COOLDOWN_SECONDS = 30;
const MODEM_POLL_MS = 15_000;

type Step = "phone" | "code" | "verified";
type ModemState = ModemStatus | "unknown" | "offline";

export default function PhoneVerification() {
  const [step, setStep] = useState<Step>("phone");
  const [phone, setPhone] = useState("");
  const [code, setCode] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  // Deadlines are epoch ms; `now` ticks once a second to drive countdowns.
  const [now, setNow] = useState(0);
  const [expiresAt, setExpiresAt] = useState<number | null>(null);
  const [resendAt, setResendAt] = useState<number | null>(null);
  const [blockedUntil, setBlockedUntil] = useState<number | null>(null);

  const [modem, setModem] = useState<ModemState>("unknown");
  const codeInput = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    let cancelled = false;

    async function poll() {
      const res = await getModemStatus();
      if (!cancelled) setModem(res.ok ? res.data.status : "offline");
    }

    poll();
    const id = setInterval(poll, MODEM_POLL_MS);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, []);

  const secondsUntil = (deadline: number | null) =>
    deadline ? Math.max(0, Math.ceil((deadline - now) / 1000)) : 0;

  const expiresIn = secondsUntil(expiresAt);
  const resendIn = secondsUntil(resendAt);
  const blockedFor = secondsUntil(blockedUntil);

  async function requestCode() {
    setPending(true);
    setError(null);
    setNotice(null);

    const res = await sendCode(phone.trim());
    const t = Date.now();
    setNow(t);
    setPending(false);

    if (res.ok) {
      setStep("code");
      setCode("");
      setExpiresAt(t + res.data.expires_in_seconds * 1000);
      setResendAt(t + RESEND_COOLDOWN_SECONDS * 1000);
      setNotice(`We sent a ${CODE_LENGTH}-digit code to ${phone.trim()}.`);
      requestAnimationFrame(() => codeInput.current?.focus());
      return;
    }

    if (res.error.retry_after_seconds) {
      setBlockedUntil(t + res.error.retry_after_seconds * 1000);
    }
    setError(res.error);
  }

  async function submitCode(value: string) {
    if (value.length !== CODE_LENGTH || pending) return;

    setPending(true);
    setError(null);

    const res = await verifyCode(phone.trim(), value);
    setPending(false);

    if (res.ok) {
      setStep("verified");
      setNotice(null);
      return;
    }

    setError(res.error);
    setCode("");
    codeInput.current?.focus();

    // The code is gone server-side; the only way forward is a new one.
    if (["too_many_attempts", "expired_or_missing"].includes(res.error.error)) {
      setExpiresAt(null);
      setResendAt(null);
    }
  }

  function onPhoneSubmit(e: FormEvent) {
    e.preventDefault();
    requestCode();
  }

  function onCodeSubmit(e: FormEvent) {
    e.preventDefault();
    submitCode(code);
  }

  function onCodeChange(raw: string) {
    const digits = raw.replace(/\D/g, "").slice(0, CODE_LENGTH);
    setCode(digits);
    if (digits.length === CODE_LENGTH) submitCode(digits);
  }

  function startOver() {
    setStep("phone");
    setCode("");
    setError(null);
    setNotice(null);
    setExpiresAt(null);
    setResendAt(null);
  }

  const codeExpired = step === "code" && expiresAt !== null && expiresIn === 0;

  return (
    <div className="w-full max-w-md">
      <div className="rounded-2xl border border-zinc-200 bg-white p-8 shadow-sm dark:border-zinc-800 dark:bg-zinc-950">
        <div className="mb-6 flex items-start justify-between gap-4">
          <div className="flex h-11 w-11 items-center justify-center rounded-xl bg-emerald-50 text-emerald-600 dark:bg-emerald-950 dark:text-emerald-400">
            {step === "verified" ? (
              <CircleCheck className="h-6 w-6" aria-hidden />
            ) : (
              <ShieldCheck className="h-6 w-6" aria-hidden />
            )}
          </div>
          <ModemBadge status={modem} />
        </div>

        {step === "phone" && (
          <form onSubmit={onPhoneSubmit} noValidate>
            <h1 className="text-2xl font-semibold tracking-tight">
              Verify your phone number
            </h1>
            <p className="mt-2 text-sm text-zinc-600 dark:text-zinc-400">
              We&apos;ll text you a {CODE_LENGTH}-digit verification code.
            </p>

            <label htmlFor="phone" className="mt-6 block text-sm font-medium">
              Phone number
            </label>
            <div className="relative mt-2">
              <Smartphone
                className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-zinc-400"
                aria-hidden
              />
              <input
                id="phone"
                type="tel"
                inputMode="tel"
                autoComplete="tel"
                placeholder="+254 712 345 678"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                aria-describedby="phone-hint"
                aria-invalid={error?.error === "invalid_phone"}
                className="w-full rounded-lg border border-zinc-300 bg-transparent py-2.5 pl-9 pr-3 text-base outline-none transition focus:border-emerald-500 focus:ring-2 focus:ring-emerald-500/20 aria-[invalid=true]:border-red-500 dark:border-zinc-700"
                autoFocus
              />
            </div>
            <p id="phone-hint" className="mt-1.5 text-xs text-zinc-500">
              International format with country code, e.g. +254712345678.
            </p>

            <Feedback error={error} blockedFor={blockedFor} />

            <SubmitButton
              pending={pending}
              disabled={!phone.trim() || blockedFor > 0}
            >
              {blockedFor > 0
                ? `Try again in ${formatDuration(blockedFor)}`
                : "Send code"}
            </SubmitButton>
          </form>
        )}

        {step === "code" && (
          <form onSubmit={onCodeSubmit} noValidate>
            <button
              type="button"
              onClick={startOver}
              className="mb-4 inline-flex items-center gap-1 text-sm text-zinc-500 hover:text-zinc-900 dark:hover:text-zinc-100"
            >
              <ArrowLeft className="h-4 w-4" aria-hidden /> Change number
            </button>

            <h1 className="text-2xl font-semibold tracking-tight">
              Enter the code
            </h1>
            {notice && (
              <p className="mt-2 flex items-start gap-2 text-sm text-zinc-600 dark:text-zinc-400">
                <MessageSquareText className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />
                {notice}
              </p>
            )}

            <label htmlFor="code" className="sr-only">
              Verification code
            </label>
            <input
              id="code"
              ref={codeInput}
              type="text"
              inputMode="numeric"
              autoComplete="one-time-code"
              pattern="\d*"
              maxLength={CODE_LENGTH}
              placeholder={"•".repeat(CODE_LENGTH)}
              value={code}
              onChange={(e) => onCodeChange(e.target.value)}
              disabled={pending || codeExpired}
              aria-invalid={error?.error === "invalid_code"}
              className="mt-6 w-full rounded-lg border border-zinc-300 bg-transparent py-3 text-center font-mono text-3xl tracking-[0.5em] outline-none transition placeholder:text-zinc-300 focus:border-emerald-500 focus:ring-2 focus:ring-emerald-500/20 disabled:opacity-50 aria-[invalid=true]:border-red-500 dark:border-zinc-700 dark:placeholder:text-zinc-700"
            />

            <p className="mt-2 text-xs text-zinc-500" aria-live="polite">
              {expiresAt === null
                ? "This code is no longer valid. Request a new one."
                : codeExpired
                  ? "This code has expired. Request a new one."
                  : `Code expires in ${formatDuration(expiresIn)}.`}
            </p>

            <Feedback error={error} blockedFor={blockedFor} />

            <SubmitButton
              pending={pending}
              disabled={code.length !== CODE_LENGTH || codeExpired}
            >
              Verify
            </SubmitButton>

            <button
              type="button"
              onClick={requestCode}
              disabled={pending || resendIn > 0 || blockedFor > 0}
              className="mt-3 inline-flex w-full items-center justify-center gap-2 rounded-lg py-2 text-sm font-medium text-emerald-700 transition hover:bg-emerald-50 disabled:cursor-not-allowed disabled:text-zinc-400 disabled:hover:bg-transparent dark:text-emerald-400 dark:hover:bg-emerald-950"
            >
              <RotateCw className="h-4 w-4" aria-hidden />
              {blockedFor > 0
                ? `Resend available in ${formatDuration(blockedFor)}`
                : resendIn > 0
                  ? `Resend code in ${resendIn}s`
                  : "Resend code"}
            </button>
          </form>
        )}

        {step === "verified" && (
          <div>
            <h1 className="text-2xl font-semibold tracking-tight">
              Phone number verified
            </h1>
            <p className="mt-2 text-sm text-zinc-600 dark:text-zinc-400">
              <span className="font-medium text-zinc-900 dark:text-zinc-100">
                {phone.trim()}
              </span>{" "}
              has been successfully verified.
            </p>
            <button
              type="button"
              onClick={() => {
                startOver();
                setPhone("");
              }}
              className="mt-6 w-full rounded-lg border border-zinc-300 py-2.5 text-sm font-medium transition hover:bg-zinc-50 dark:border-zinc-700 dark:hover:bg-zinc-900"
            >
              Verify another number
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

function SubmitButton({
  pending,
  disabled,
  children,
}: {
  pending: boolean;
  disabled: boolean;
  children: ReactNode;
}) {
  return (
    <button
      type="submit"
      disabled={pending || disabled}
      className="mt-6 inline-flex w-full items-center justify-center gap-2 rounded-lg bg-emerald-600 py-2.5 text-sm font-semibold text-white transition hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-50"
    >
      {pending && <LoaderCircle className="h-4 w-4 animate-spin" aria-hidden />}
      {children}
    </button>
  );
}

function Feedback({
  error,
  blockedFor,
}: {
  error: ApiError | null;
  blockedFor: number;
}) {
  if (!error) return null;

  // Rate-limit messages carry a server-computed wait; show a live one instead.
  const message =
    error.error === "rate_limited" && blockedFor > 0
      ? `Too many codes requested for this number. Try again in ${formatDuration(blockedFor)}.`
      : error.message;

  return (
    <div
      role="alert"
      className="mt-4 flex items-start gap-2 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700 dark:border-red-900 dark:bg-red-950/50 dark:text-red-300"
    >
      <CircleAlert className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />
      <span>{message}</span>
    </div>
  );
}

const MODEM_LABELS: Record<ModemState, { label: string; dot: string }> = {
  ready: { label: "SMS gateway online", dot: "bg-emerald-500" },
  busy: { label: "SMS gateway busy", dot: "bg-amber-500" },
  disconnected: { label: "Gateway phone offline", dot: "bg-red-500" },
  offline: { label: "Server unreachable", dot: "bg-red-500" },
  unknown: { label: "Checking gateway…", dot: "bg-zinc-400" },
};

function ModemBadge({ status }: { status: ModemState }) {
  const { label, dot } = MODEM_LABELS[status];
  return (
    <span className="inline-flex items-center gap-1.5 rounded-full border border-zinc-200 px-2.5 py-1 text-xs text-zinc-600 dark:border-zinc-800 dark:text-zinc-400">
      <span className={`h-1.5 w-1.5 rounded-full ${dot}`} aria-hidden />
      {label}
    </span>
  );
}

function formatDuration(totalSeconds: number) {
  const m = Math.floor(totalSeconds / 60);
  const s = totalSeconds % 60;
  return m > 0 ? `${m}:${s.toString().padStart(2, "0")} min` : `${s}s`;
}
