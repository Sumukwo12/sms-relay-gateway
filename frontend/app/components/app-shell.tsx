"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useCallback, useEffect, useState, type ComponentType, type ReactNode } from "react";
import { LogOut, Menu, MessageSquareText, X } from "lucide-react";
import { getMe, logout, type User } from "../lib/account";
import { SessionContext } from "../dashboard/session";
import { Spinner } from "./ui";

export type NavItem = { href: string; label: string; icon: ComponentType<{ className?: string }> };

/**
 * Signed-in page frame: checks the session (sending visitors to /login),
 * optionally admins only, and shows the sidebar.
 */
export default function AppShell({
  nav,
  footerLink,
  adminOnly = false,
  badge,
  banner,
  children,
}: {
  nav: (user: User) => NavItem[];
  footerLink?: (user: User) => NavItem | null;
  adminOnly?: boolean;
  badge?: string;
  banner?: (user: User) => ReactNode;
  children: ReactNode;
}) {
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
      if (!res.ok) router.replace("/login");
      else if (adminOnly && res.data.user.role !== "admin") router.replace("/dashboard");
      else setUser(res.data.user);
    }

    check();
    return () => {
      cancelled = true;
    };
  }, [router, version, adminOnly]);

  if (!user) return <Spinner />;

  async function signOut() {
    await logout();
    router.replace("/login");
  }

  const items = nav(user);
  const extra = footerLink?.(user);
  const roots = new Set(["/dashboard", "/admin"]);

  return (
    <SessionContext.Provider value={{ user, refresh }}>
      <div className="flex min-h-full flex-1 flex-col bg-zinc-50 font-sans text-zinc-900 md:flex-row dark:bg-black dark:text-zinc-100">
        <aside className="border-b border-zinc-200 bg-white md:sticky md:top-0 md:flex md:h-screen md:w-60 md:flex-col md:border-b-0 md:border-r dark:border-zinc-800 dark:bg-zinc-950">
          <div className="flex items-center justify-between px-4 py-4">
            <Link href={items[0]?.href ?? "/"} className="flex items-center gap-2 font-semibold">
              <span className="flex h-8 w-8 items-center justify-center rounded-lg bg-emerald-600 text-white">
                <MessageSquareText className="h-4 w-4" aria-hidden />
              </span>
              SMS Gateway
              {badge && (
                <span className="rounded bg-zinc-900 px-1.5 py-0.5 text-[10px] font-semibold uppercase text-white dark:bg-zinc-100 dark:text-zinc-900">
                  {badge}
                </span>
              )}
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
            <nav className="space-y-1">
              {items.map(({ href, label, icon: Icon }) => {
                const active = roots.has(href) ? pathname === href : pathname.startsWith(href);
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

            <div className="mt-4 space-y-1 border-t border-zinc-200 pt-4 md:mt-auto dark:border-zinc-800">
              {extra && (
                <Link
                  href={extra.href}
                  className="flex items-center gap-2.5 rounded-lg px-3 py-2 text-sm font-medium text-zinc-600 hover:bg-zinc-100 dark:text-zinc-400 dark:hover:bg-zinc-900"
                >
                  <extra.icon className="h-4 w-4" aria-hidden />
                  {extra.label}
                </Link>
              )}
              <p className="truncate px-3 pt-1 text-xs text-zinc-500" title={user.email}>
                {user.email}
              </p>
              <button
                type="button"
                onClick={signOut}
                className="flex w-full items-center gap-2.5 rounded-lg px-3 py-2 text-sm font-medium text-zinc-600 hover:bg-zinc-100 dark:text-zinc-400 dark:hover:bg-zinc-900"
              >
                <LogOut className="h-4 w-4" aria-hidden /> Sign out
              </button>
            </div>
          </div>
        </aside>

        <main className="mx-auto w-full max-w-6xl flex-1 px-4 py-8 sm:px-8">
          {banner?.(user)}
          {children}
        </main>
      </div>
    </SessionContext.Provider>
  );
}
