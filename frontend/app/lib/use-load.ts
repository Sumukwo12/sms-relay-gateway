"use client";

import { useCallback, useEffect, useState } from "react";
import type { ApiError, Result } from "./api";

/**
 * Load data from the API on mount (and every `pollMs`, if given).
 * `reload()` fetches again, e.g. after a change.
 */
export function useLoad<T>(load: () => Promise<Result<T>>, pollMs?: number) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<ApiError | null>(null);
  const [version, setVersion] = useState(0);

  const reload = useCallback(() => setVersion((v) => v + 1), []);

  useEffect(() => {
    let cancelled = false;

    async function run() {
      const res = await load();
      if (cancelled) return;
      if (res.ok) {
        setData(res.data);
        setError(null);
      } else {
        setError(res.error);
      }
    }

    run();
    const id = pollMs ? setInterval(run, pollMs) : undefined;
    return () => {
      cancelled = true;
      if (id) clearInterval(id);
    };
  }, [load, pollMs, version]);

  return { data, error, reload };
}
