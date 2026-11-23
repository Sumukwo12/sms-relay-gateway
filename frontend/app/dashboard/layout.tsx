import type { Metadata } from "next";
import DashboardShell from "./dashboard-shell";

// Signed-in pages: keep them out of search results
export const metadata: Metadata = {
  title: "Dashboard",
  robots: { index: false, follow: false },
};

export default function DashboardLayout({ children }: LayoutProps<"/dashboard">) {
  return <DashboardShell>{children}</DashboardShell>;
}
