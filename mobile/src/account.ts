// Account sign-in for the relay: the server links this phone to the user's
// account and returns a device token for the WebSocket (see backend
// AppController). Nothing here stores the password.

import { Platform } from 'react-native';
import Constants from 'expo-constants';

export const DEFAULT_SERVER = 'https://sms.strand.co.ke';

export type AccountUser = {
  id: number;
  email: string;
  name: string | null;
  role: 'admin' | 'user';
  status: 'pending' | 'approved' | 'suspended';
  daily_limit: number;
};

export type AccountDevice = { id: number; name: string };

export type SignInResult = {
  device_token: string;
  socket_url: string;
  device: AccountDevice;
  user: AccountUser;
};

export type ApiResult<T> = { ok: true; data: T } | { ok: false; message: string; status: number };

async function call<T>(
  base: string,
  path: string,
  init: { method?: string; body?: unknown; token?: string } = {}
): Promise<ApiResult<T>> {
  try {
    const res = await fetch(`${base}${path}`, {
      method: init.method ?? 'GET',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
        ...(init.token ? { Authorization: `Bearer ${init.token}` } : {}),
      },
      body: init.body === undefined ? undefined : JSON.stringify(init.body),
    });
    const json = await res.json().catch(() => null);

    if (res.ok) return { ok: true, data: json as T };

    // A JSON error from the gateway explains itself; anything else (an HTML
    // 404 page, a proxy error) means the address doesn't reach the gateway API
    const message =
      json && typeof json.message === 'string'
        ? json.message
        : `HTTP ${res.status} from ${base}${path}. Check the server address: it should be the gateway's website, e.g. ${DEFAULT_SERVER}`;
    return { ok: false, status: res.status, message };
  } catch {
    return { ok: false, status: 0, message: `Cannot reach ${base}. Check the address and your connection.` };
  }
}

function deviceDetails() {
  const c = (Platform.constants ?? {}) as { Manufacturer?: string; Model?: string };
  const model = [c.Manufacturer, c.Model].filter(Boolean).join(' ') || undefined;
  return {
    device_name: Constants.deviceName || model || 'Android phone',
    model,
    app_version: Constants.expoConfig?.version,
  };
}

export function signIn(base: string, email: string, password: string) {
  return call<SignInResult>(base, '/api/app/login', {
    method: 'POST',
    body: { email: email.trim(), password, ...deviceDetails() },
  });
}

/** Create the account, then sign this phone in to it. */
export async function signUp(
  base: string,
  email: string,
  password: string,
  name: string
): Promise<ApiResult<SignInResult>> {
  const created = await call<{ user: AccountUser }>(base, '/api/auth/register', {
    method: 'POST',
    body: { email: email.trim(), password, name: name.trim() },
  });
  if (!created.ok) return created;
  return signIn(base, email, password);
}

export function fetchMe(base: string, token: string) {
  return call<{ user: AccountUser; device: AccountDevice }>(base, '/api/app/me', { token });
}

export function signOutDevice(base: string, token: string) {
  return call<{ success: true }>(base, '/api/app/logout', { method: 'POST', token });
}
