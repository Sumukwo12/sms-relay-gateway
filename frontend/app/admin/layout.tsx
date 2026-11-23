"use client";

import { LayoutDashboard, ListChecks, Smartphone, UserRound, Users } from "lucide-react";
import AppShell, { type NavItem } from "../components/app-shell";

const NAV: NavItem[] = [
  { href: "/admin", label: "System overview", icon: LayoutDashboard },
  { href: "/admin/users", label: "Users", icon: Users },
  { href: "/admin/phones", label: "All phones", icon: Smartphone },
  { href: "/admin/messages", label: "All messages", icon: ListChecks },
];

export default function AdminLayout({ children }: LayoutProps<"/admin">) {
  return (
    <AppShell
      adminOnly
      badge="Admin"
      nav={() => NAV}
      footerLink={() => ({ href: "/dashboard", label: "My own gateway", icon: UserRound })}
    >
      {children}
    </AppShell>
  );
}
