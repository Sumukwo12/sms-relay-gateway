"use client";

import { useEffect, useState } from "react";
import { CopyButton } from "./ui";

/** The OpenAPI link to import into Postman, for whatever host serves this page. */
export default function PostmanUrl() {
  const [url, setUrl] = useState("https://sms.strand.co.ke/openapi.json");

  useEffect(() => {
    // The page is prerendered; use the real host once it runs in the browser
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setUrl(`${window.location.origin}/openapi.json`);
  }, []);

  return (
    <span className="mt-2 flex items-center gap-2 rounded-lg bg-zinc-100 px-2 py-1.5 dark:bg-zinc-900">
      <code className="min-w-0 flex-1 truncate font-mono text-xs text-zinc-800 dark:text-zinc-200">{url}</code>
      <CopyButton value={url} />
    </span>
  );
}
