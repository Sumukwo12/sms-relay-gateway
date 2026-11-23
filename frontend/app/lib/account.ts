// Dashboard, admin and sign-in calls (session cookie). See backend/router.ex.

import { request } from "./api";

export type Role = "admin" | "user";
export type UserStatus = "pending" | "approved" | "suspended";

export type User = {
  id: number;
  email: string;
  name: string | null;
  role: Role;
  status: UserStatus;
  daily_limit: number;
  created_at: string;
};

export type Device = {
  id: number;
  name: string;
  model: string | null;
  app_version: string | null;
  online: boolean;
  battery: number | null;
  charging: boolean | null;
  signal: number | null;
  last_seen_at: string | null;
  created_at: string;
  owner?: { id: number; email: string };
};

export type ApiKey = {
  id: number;
  name: string;
  prefix: string;
  mode: "live" | "test";
  last_used_at: string | null;
  created_at: string;
};

export type MessageStatus = "queued" | "sending" | "sent" | "delivered" | "failed";

export type Message = {
  id: string;
  kind: "otp" | "notification";
  to: string;
  status: MessageStatus;
  attempts: number;
  error: string | null;
  reference: string | null;
  segments: number;
  device_id: number | null;
  created_at: string;
  sent_at: string | null;
  delivered_at: string | null;
  failed_at: string | null;
  expires_at: string;
  test: boolean;
};

export type Overview = {
  user: User;
  webhook_secret: string;
  webhook_url: string | null;
  otp_template: string | null;
  usage: { sent_last_24h: number; queued: number; daily_limit: number };
  gateway_online: boolean;
  devices: Device[];
  api_keys: number;
};

export type AdminUser = User & {
  sent_last_24h: number;
  custom_daily_limit: number | null;
  online: boolean;
};

export type AdminOverview = {
  users: Partial<Record<UserStatus, number>>;
  devices: { total: number; online: number };
  messages: { sent_last_24h: number; queued: number };
  server_gateway_online: boolean;
};

const post = (body?: unknown) => ({ method: "POST", body: JSON.stringify(body ?? {}) });
const patch = (body: unknown) => ({ method: "PATCH", body: JSON.stringify(body) });
const del = () => ({ method: "DELETE", body: "{}" });

// ── Sign-in ─────────────────────────────────────────────────────────────────

export const getMe = () => request<{ user: User }>("/api/auth/me");

export const register = (email: string, password: string, name: string) =>
  request<{ user: User }>("/api/auth/register", post({ email, password, name }));

export const login = (email: string, password: string) =>
  request<{ user: User }>("/api/auth/login", post({ email, password }));

export const logout = () => request<{ success: true }>("/api/auth/logout", post());

// ── Account ─────────────────────────────────────────────────────────────────

export const getOverview = () => request<Overview>("/api/account");

export const changePassword = (current_password: string, new_password: string) =>
  request<{ success: true }>("/api/account/password", post({ current_password, new_password }));

export const rotateWebhookSecret = () =>
  request<{ webhook_secret: string }>("/api/account/webhook-secret", post());

export const getDevices = () => request<{ devices: Device[] }>("/api/account/devices");

export const renameDevice = (id: number, name: string) =>
  request<{ device: Device }>(`/api/account/devices/${id}`, patch({ name }));

export const removeDevice = (id: number) =>
  request<{ success: true }>(`/api/account/devices/${id}`, del());

export const getApiKeys = () => request<{ api_keys: ApiKey[] }>("/api/account/api-keys");

export const createApiKey = (name: string, mode: "live" | "test" = "live") =>
  request<{ api_key: ApiKey; key: string }>("/api/account/api-keys", post({ name, mode }));

export const updateSettings = (settings: { webhook_url?: string; otp_template?: string }) =>
  request<{ webhook_url: string | null; otp_template: string | null }>(
    "/api/account/settings",
    patch(settings),
  );

export const revokeApiKey = (id: number) =>
  request<{ success: true }>(`/api/account/api-keys/${id}`, del());

export const getMessages = () => request<{ messages: Message[] }>("/api/account/messages");

export const consoleSms = (to: string, body: string, device_id: number | null) =>
  request<{ message: Message }>("/api/account/console/sms", post({ to, body, device_id }));

export const consoleOtpSend = (phone: string, device_id: number | null) =>
  request<{ message: Message; expires_in_seconds: number }>(
    "/api/account/console/otp/send",
    post({ phone, device_id }),
  );

export const consoleOtpVerify = (phone: string, code: string) =>
  request<{ verified: true }>("/api/account/console/otp/verify", post({ phone, code }));

// ── Admin ───────────────────────────────────────────────────────────────────

export const getAdminOverview = () => request<AdminOverview>("/api/admin/overview");

export const getAdminUsers = () => request<{ users: AdminUser[] }>("/api/admin/users");

export const updateAdminUser = (
  id: number,
  changes: Partial<{ status: UserStatus; role: Role; daily_limit: number | null }>,
) => request<{ user: User }>(`/api/admin/users/${id}`, patch(changes));

export const getAdminDevices = () => request<{ devices: Device[] }>("/api/admin/devices");

export type AdminMessage = Message & { owner: string };

export const getAdminMessages = () =>
  request<{ messages: AdminMessage[] }>("/api/admin/messages");
