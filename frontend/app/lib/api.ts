// Typed client for the Phoenix SMS gateway API (backend/).

export const API_URL = (
  process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:4000"
).replace(/\/$/, "");

export type ModemStatus = "ready" | "busy" | "disconnected";

export type ApiError = {
  success: false;
  error: string;
  message: string;
  field?: string;
  retry_after_seconds?: number;
  detail?: string;
};

export type SendCodeOk = {
  success: true;
  message: string;
  has_pending: boolean;
  expires_in_seconds: number;
};

export type VerifyCodeOk = {
  success: true;
  verified: true;
  message: string;
};

export type Result<T> = { ok: true; data: T } | { ok: false; error: ApiError };

export async function request<T>(path: string, init?: RequestInit): Promise<Result<T>> {
  try {
    const res = await fetch(`${API_URL}${path}`, {
      ...init,
      // The dashboard signs in with an HttpOnly session cookie
      credentials: "include",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        ...init?.headers,
      },
    });

    const body = await res.json().catch(() => null);

    if (res.ok) return { ok: true, data: body as T };

    return {
      ok: false,
      error:
        body && typeof body.error === "string"
          ? (body as ApiError)
          : {
              success: false,
              error: "http_error",
              message: `Unexpected response from server (HTTP ${res.status}).`,
            },
    };
  } catch {
    return {
      ok: false,
      error: {
        success: false,
        error: "network_error",
        message: `Cannot reach the gateway server at ${API_URL || "this site"}.`,
      },
    };
  }
}

export function sendCode(phone: string) {
  return request<SendCodeOk>("/api/send-code", {
    method: "POST",
    body: JSON.stringify({ phone }),
  });
}

export function verifyCode(phone: string, code: string) {
  return request<VerifyCodeOk>("/api/verify-code", {
    method: "POST",
    body: JSON.stringify({ phone, code }),
  });
}

export function getModemStatus() {
  return request<{ status: ModemStatus; ready: boolean }>("/api/modem/status");
}
