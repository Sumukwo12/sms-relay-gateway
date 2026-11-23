import type { Metadata } from "next";
import Link from "next/link";
import PhoneVerification from "../components/phone-verification";

export const metadata: Metadata = { title: "Try it · SMS Gateway" };

export default function DemoPage() {
  return (
    <main className="flex flex-1 flex-col items-center justify-center bg-zinc-50 px-4 py-16 font-sans text-zinc-900 dark:bg-black dark:text-zinc-100">
      <PhoneVerification />
      <p className="mt-6 max-w-md text-center text-xs text-zinc-500">
        This demo sends through the gateway owner&apos;s phone.{" "}
        <Link href="/register" className="font-medium text-emerald-700 underline dark:text-emerald-400">
          Create an account
        </Link>{" "}
        to send through your own.
      </p>
    </main>
  );
}
