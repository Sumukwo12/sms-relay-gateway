"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";
import { MessageSquareText } from "lucide-react";
import { login, register } from "../lib/account";
import type { ApiError } from "../lib/api";
import { Alert, Button, Field } from "./ui";

export default function AuthForm({ mode }: { mode: "login" | "register" }) {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [name, setName] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);

  const isRegister = mode === "register";

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setPending(true);
    setError(null);

    const res = isRegister
      ? await register(email.trim(), password, name.trim())
      : await login(email.trim(), password);

    if (res.ok) {
      router.push("/dashboard");
      return;
    }

    setPending(false);
    setError(res.error);
  }

  return (
    <main className="flex flex-1 flex-col items-center justify-center bg-zinc-50 px-4 py-16 font-sans text-zinc-900 dark:bg-black dark:text-zinc-100">
      <Link href="/" className="mb-8 flex items-center gap-2 font-semibold">
        <span className="flex h-8 w-8 items-center justify-center rounded-lg bg-emerald-600 text-white">
          <MessageSquareText className="h-4 w-4" aria-hidden />
        </span>
        SMS Gateway
      </Link>

      <form
        onSubmit={onSubmit}
        noValidate
        className="w-full max-w-sm space-y-4 rounded-2xl border border-zinc-200 bg-white p-8 shadow-sm dark:border-zinc-800 dark:bg-zinc-950"
      >
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">
            {isRegister ? "Create your account" : "Sign in"}
          </h1>
          <p className="mt-1 text-sm text-zinc-600 dark:text-zinc-400">
            {isRegister
              ? "Send SMS through your own Android phone and SIM."
              : "Welcome back to your SMS gateway."}
          </p>
        </div>

        {isRegister && (
          <Field
            id="name"
            label="Name"
            autoComplete="name"
            value={name}
            onChange={(e) => setName(e.target.value)}
          />
        )}
        <Field
          id="email"
          label="Email"
          type="email"
          autoComplete="email"
          required
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          aria-invalid={error?.field === "email"}
          autoFocus
        />
        <Field
          id="password"
          label="Password"
          type="password"
          autoComplete={isRegister ? "new-password" : "current-password"}
          required
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          aria-invalid={error?.field === "password"}
          hint={isRegister ? "At least 8 characters." : undefined}
        />

        {error && <Alert>{error.message}</Alert>}

        <Button type="submit" pending={pending} disabled={!email || !password} className="w-full">
          {isRegister ? "Create account" : "Sign in"}
        </Button>

        <p className="text-center text-sm text-zinc-600 dark:text-zinc-400">
          {isRegister ? "Already have an account? " : "New here? "}
          <Link
            href={isRegister ? "/login" : "/register"}
            className="font-medium text-emerald-700 hover:underline dark:text-emerald-400"
          >
            {isRegister ? "Sign in" : "Create an account"}
          </Link>
        </p>
      </form>
    </main>
  );
}
