import PhoneVerification from "./components/phone-verification";

export default function Home() {
  return (
    <main className="flex flex-1 flex-col items-center justify-center bg-zinc-50 px-4 py-16 font-sans text-zinc-900 dark:bg-black dark:text-zinc-100">
      <PhoneVerification />
      <p className="mt-6 text-center text-xs text-zinc-500">
        Codes are delivered by SMS via a USB GSM modem or an Android phone gateway.
      </p>
    </main>
  );
}
