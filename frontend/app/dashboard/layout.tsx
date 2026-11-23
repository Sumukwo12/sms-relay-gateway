"use client";

import {
  BookOpen,
  KeyRound,
  LayoutDashboard,
  ListChecks,
  Send,
  Settings,
  ShieldCheck,
  Smartphone,
} from "lucide-react";
import AppShell, { type NavItem } from "../components/app-shell";
import { Alert } from "../components/ui";

const NAV: NavItem[] = [
  { href: "/dashboard", label: "Overview", icon: LayoutDashboard },
  { href: "/dashboard/phones", label: "Phones", icon: Smartphone },
  { href: "/dashboard/keys", label: "API keys", icon: KeyRound },
  { href: "/dashboard/console", label: "Test console", icon: Send },
  { href: "/dashboard/messages", label: "Messages", icon: ListChecks },
  { href: "/dashboard/docs", label: "Integration docs", icon: BookOpen },
  { href: "/dashboard/settings", label: "Settings", icon: Settings },
];

export default function DashboardLayout({ children }: LayoutProps<"/dashboard">) {
  return (
    <AppShell
      nav={() => NAV}
      footerLink={(user) =>
        user.role === "admin" ? { href: "/admin", label: "Admin panel", icon: ShieldCheck } : null
      }
      banner={(user) =>
        user.status === "pending" && (
          <div className="mb-6">
            <Alert tone="warning">
              Your account is waiting for an administrator&apos;s approval. You can already link
              your phone and create API keys; messages will be sent once you&apos;re approved.
            </Alert>
          </div>
        )
      }
    >
      {children}
    </AppShell>
  );
}
