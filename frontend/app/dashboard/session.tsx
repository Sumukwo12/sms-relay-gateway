"use client";

import { createContext, useContext } from "react";
import type { User } from "../lib/account";

export const SessionContext = createContext<{ user: User; refresh: () => void } | null>(null);

/** The signed-in user (inside the dashboard layout only). */
export function useSession() {
  const session = useContext(SessionContext);
  if (!session) throw new Error("useSession must be used inside the dashboard layout");
  return session;
}
