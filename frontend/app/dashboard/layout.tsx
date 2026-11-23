"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import {
  BookOpen,
  KeyRound,
  LayoutDashboard,
  ListChecks,
  LogOut,
  Menu,
  MessageSquareText,
  Send,
  Settings,
  ShieldCheck,
  Smartphone,
  X,
} from "lucide-react";
import { getMe, logout, type User } from "../lib/account";
import { Alert, Spinner } from "../components/ui";
import { SessionContext } from "./session";

const NAV = [
  { href: "/dashboard", label: "Overview", icon: LayoutDashboard },
  { href: "/dashboard/phones", label: "Phones", icon: Smartphone },
  { href: "/dashboard/keys", label: "API keys", icon: KeyRound },
  { href: "/dashboard/console", label: "Test console", icon: Send },
  { href: "/dashboard/messages", label: "Messages", icon: ListChecks },
  { href: "/dashboard/docs", label: "Integration docs", icon: BookOpen },
  { href: "/dashboard/settings", label: "Settings", icon: Settings },
] as const;

export default function DashboardLayout({ children }: LayoutProps<"/dashboard">) {
  const router = useRouter();
  const pathname = usePathname();
  const [user, setUser] = useState<User | null>(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const [version, setVersion] = useState(0);

  const refresh = useCallback(() => setVersion((v) => v + 1), []);

  useEffect(() => {
    let cancelled = false;

    async function check() {
      const res = await getMe();
      if (cancelled) return;
      if (res.ok) setUser(res.data.user);
      else router.replace("/login");
    }

    check();
    return () => {
      cancelled = true;
    };
  }, [router, version]);

  if (!user) return <Spinner />;

  async function signOut() {
    await logout();
    router.replace("/login");
  }

  const nav = user.role === "admin"
    ? [...NAV, { href: "/dashboard/admin", label: "Admin", icon: ShieldCheck } as const]
    : NAV;

  const navLinks = (
    <nav className="space-y-1">
      {nav.map(({ href, label, icon: Icon }) => {
        const active = href === "/dashboard" ? pathname === href : pathname.startsWith(href);
        return (
          <Link
            key={href}
            href={href}
            onClick={() => setMenuOpen(false)}
            className={`flex items-center gap-2.5 rounded-lg px-3 py-2 text-sm font-medium transition ${
              active
                ? "bg-emerald-50 text-emerald-800 dark:bg-emerald-950 dark:text-emerald-300"
                : "text-zinc-600 hover:bg-zinc-100 dark:text-zinc-400 dark:hover:bg-zinc-900"
            }`}
          >
            <Icon className="h-4 w-4" aria-hidden />
            {label}
          </Link>
        );
      })}
    </nav>
  );

  return (
    <SessionContext.Provider value={{ user, refresh }}>
      <div className="flex min-h-full flex-1 flex-col bg-zinc-50 font-sans text-zinc-900 md:flex-row dark:bg-black dark:text-zinc-100">
        <aside className="border-b border-zinc-200 bg-white md:sticky md:top-0 md:flex md:h-screen md:w-60 md:flex-col md:border-b-0 md:border-r dark:border-zinc-800 dark:bg-zinc-950">
          <div className="flex items-center justify-between px-4 py-4">
            <Link href="/dashboard" className="flex items-center gap-2 font-semibold">
              <span className="flex h-8 w-8 items-center justify-center rounded-lg bg-emerald-600 text-white">
                <MessageSquareText className="h-4 w-4" aria-hidden />
              </span>
              SMS Gateway
            </Link>
            <button
              type="button"
              className="rounded-md p-2 md:hidden"
              onClick={() => setMenuOpen(!menuOpen)}
              aria-label={menuOpen ? "Close menu" : "Open menu"}
            >
              {menuOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
            </button>
          </div>

          <div className={`${menuOpen ? "block" : "hidden"} px-3 pb-4 md:flex md:flex-1 md:flex-col`}>
            {navLinks}
            <div className="mt-4 border-t border-zinc-200 pt-4 md:mt-auto dark:border-zinc-800">
              <p className="truncate px-3 text-xs text-zinc-500" title={user.email}>
                {user.email}
              </p>
              <button
                type="button"
                onClick={signOut}
                className="mt-1 flex w-full items-center gap-2.5 rounded-lg px-3 py-2 text-sm font-medium text-zinc-600 hover:bg-zinc-100 dark:text-zinc-400 dark:hover:bg-zinc-900"
              >
                <LogOut className="h-4 w-4" aria-hidden /> Sign out
              </button>
            </div>
          </div>
        </aside>

        <main className="mx-auto w-full max-w-5xl flex-1 px-4 py-8 sm:px-8">
          {user.status === "pending" && (
            <div className="mb-6">
              <Alert tone="warning">
                Your account is waiting for an administrator&apos;s approval. You can already link
                your phone and create API keys; messages will be sent once you&apos;re approved.
              </Alert>
            </div>
          )}
          {children}
        </main>
      </div>
    </SessionContext.Provider>
  );
}
