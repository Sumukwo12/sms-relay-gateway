// Pure helpers used by the relay, kept free of React Native imports so they
// can be unit tested with `npm test` (node:test) without a device.

import type { LogEntry } from './types';

export type SmsOutcome = { status: 'sent' | 'failed'; error: string | null };

export function isPrivateNetworkUrl(urlStr: string): boolean {
  try {
    const parsed = new URL(urlStr);
    const host = parsed.hostname.toLowerCase();
    if (
      host === 'localhost' ||
      host === '127.0.0.1' ||
      host === '::1' ||
      host.endsWith('.local')
    ) {
      return true;
    }
    if (/^10\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(host)) return true;
    const m172 = host.match(/^172\.(\d{1,3})\.\d{1,3}\.\d{1,3}$/);
    if (m172) {
      const second = parseInt(m172[1], 10);
      if (second >= 16 && second <= 31) return true;
    }
    if (/^192\.168\.\d{1,3}\.\d{1,3}$/.test(host)) return true;
    return false;
  } catch {
    return false;
  }
}

/**
 * The Phoenix client appends "/websocket" to the endpoint itself, so a URL
 * pasted as ".../phone/websocket" would connect to ".../phone/websocket/websocket"
 * and 404. Accept both forms.
 */
export function normalizeSocketUrl(urlStr: string): string {
  return urlStr.trim().replace(/\/+$/, '').replace(/\/websocket$/i, '');
}

export function getUrlSecurityWarning(urlStr: string): string | null {
  if (!urlStr) return null;
  const lower = urlStr.trim().toLowerCase();
  if (lower.startsWith('ws://') && !isPrivateNetworkUrl(urlStr)) {
    return 'Security Warning: Unencrypted ws:// on a public host. Use wss:// for production to prevent interception.';
  }
  return null;
}

export function isValidE164(phone: string): boolean {
  const cleaned = phone.replace(/[\s\-().]/g, '');
  return /^\+[1-9]\d{7,14}$/.test(cleaned);
}

/**
 * Final send result per message id, rebuilt from the persisted log. After an
 * app restart the server may resend an id we already handled (its earlier
 * result was lost); answering from this map stops that SMS from being
 * reported as failed, and from being sent twice.
 */
export function resultsFromLogs(logs: LogEntry[]): Map<string, SmsOutcome> {
  const results = new Map<string, SmsOutcome>();
  // Logs are newest first; insert oldest first so Map order stays by age
  for (let i = logs.length - 1; i >= 0; i--) {
    const entry = logs[i];
    results.set(entry.id, {
      status: entry.status === 'failed' ? 'failed' : 'sent',
      error: entry.status === 'failed' ? (entry.error ?? null) : null,
    });
  }
  return results;
}

/** Add `id` to a bounded list of delivery reports waiting to reach the server. */
export function addPendingDelivery(pending: string[], id: string, max = 500): string[] {
  if (pending.includes(id)) return pending;
  const updated = [...pending, id];
  return updated.length > max ? updated.slice(updated.length - max) : updated;
}
