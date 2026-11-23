import * as SecureStore from 'expo-secure-store';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { LogEntry, RelaySettings, RelayStats } from './types';
import { addPendingDelivery } from './relayLogic';

const SECURE_KEY_URL = 'sms_relay_server_url';
const SECURE_KEY_TOKEN = 'sms_relay_auth_token';
const ASYNC_KEY_SUB_ID = '@sms_relay_sub_id';
const ASYNC_KEY_LOGS = '@sms_relay_message_logs_v1';
const ASYNC_KEY_PENDING_DELIVERIES = '@sms_relay_pending_deliveries_v1';
const ASYNC_KEY_SERVICE_ENABLED = '@sms_relay_service_enabled';
const MAX_LOG_ENTRIES = 200;

export async function saveSettings(settings: RelaySettings): Promise<void> {
  await SecureStore.setItemAsync(SECURE_KEY_URL, settings.serverUrl);
  await SecureStore.setItemAsync(SECURE_KEY_TOKEN, settings.token);
  if (settings.selectedSubId !== null) {
    await AsyncStorage.setItem(ASYNC_KEY_SUB_ID, settings.selectedSubId.toString());
  } else {
    await AsyncStorage.removeItem(ASYNC_KEY_SUB_ID);
  }
}

export async function loadSettings(): Promise<RelaySettings> {
  const serverUrl = (await SecureStore.getItemAsync(SECURE_KEY_URL)) || '';
  const token = (await SecureStore.getItemAsync(SECURE_KEY_TOKEN)) || '';
  const subIdStr = await AsyncStorage.getItem(ASYNC_KEY_SUB_ID);
  const selectedSubId = subIdStr !== null ? parseInt(subIdStr, 10) : null;

  return {
    serverUrl,
    token,
    selectedSubId,
  };
}

// ── Signed-in account (not secret: the device token lives in SecureStore) ──

const ASYNC_KEY_ACCOUNT = '@sms_relay_account_v1';

export interface StoredAccount {
  server: string;
  email: string;
  deviceName: string;
}

export async function saveAccount(account: StoredAccount | null): Promise<void> {
  if (account) await AsyncStorage.setItem(ASYNC_KEY_ACCOUNT, JSON.stringify(account));
  else await AsyncStorage.removeItem(ASYNC_KEY_ACCOUNT);
}

export async function loadAccount(): Promise<StoredAccount | null> {
  try {
    const raw = await AsyncStorage.getItem(ASYNC_KEY_ACCOUNT);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

export async function getLogs(): Promise<LogEntry[]> {
  try {
    const raw = await AsyncStorage.getItem(ASYNC_KEY_LOGS);
    if (!raw) return [];
    return JSON.parse(raw);
  } catch (err) {
    console.error('[Storage] Error loading logs:', err);
    return [];
  }
}

export async function addLogEntry(entry: LogEntry): Promise<LogEntry[]> {
  try {
    const currentLogs = await getLogs();
    // Prepend newest entry and keep at most MAX_LOG_ENTRIES
    const updated = [entry, ...currentLogs.filter((l) => l.id !== entry.id)].slice(0, MAX_LOG_ENTRIES);
    await AsyncStorage.setItem(ASYNC_KEY_LOGS, JSON.stringify(updated));
    return updated;
  } catch (err) {
    console.error('[Storage] Error saving log entry:', err);
    return [];
  }
}

export async function updateLogDelivery(id: string): Promise<LogEntry[]> {
  try {
    const currentLogs = await getLogs();
    let changed = false;
    const updated = currentLogs.map((entry) => {
      if (entry.id === id && entry.status === 'sent') {
        changed = true;
        return { ...entry, status: 'delivered' as const };
      }
      return entry;
    });

    if (changed) {
      await AsyncStorage.setItem(ASYNC_KEY_LOGS, JSON.stringify(updated));
    }
    return updated;
  } catch (err) {
    console.error('[Storage] Error updating log delivery:', err);
    return [];
  }
}

// ── Delivery reports not yet acknowledged by the server ────────────────────

// Reports can arrive together; run the read-modify-write updates one at a
// time so none is lost.
let pendingWrites: Promise<void> = Promise.resolve();
function serializePendingWrite(fn: () => Promise<void>): Promise<void> {
  pendingWrites = pendingWrites.then(fn, fn);
  return pendingWrites;
}

export async function getPendingDeliveries(): Promise<string[]> {
  try {
    const raw = await AsyncStorage.getItem(ASYNC_KEY_PENDING_DELIVERIES);
    return raw ? JSON.parse(raw) : [];
  } catch (err) {
    console.error('[Storage] Error loading pending deliveries:', err);
    return [];
  }
}

export function addPendingDeliveryId(id: string): Promise<void> {
  return serializePendingWrite(async () => {
    try {
      const updated = addPendingDelivery(await getPendingDeliveries(), id);
      await AsyncStorage.setItem(ASYNC_KEY_PENDING_DELIVERIES, JSON.stringify(updated));
    } catch (err) {
      console.error('[Storage] Error saving pending delivery:', err);
    }
  });
}

export function removePendingDeliveryId(id: string): Promise<void> {
  return serializePendingWrite(async () => {
    try {
      const current = await getPendingDeliveries();
      const updated = current.filter((pendingId) => pendingId !== id);
      if (updated.length !== current.length) {
        await AsyncStorage.setItem(ASYNC_KEY_PENDING_DELIVERIES, JSON.stringify(updated));
      }
    } catch (err) {
      console.error('[Storage] Error removing pending delivery:', err);
    }
  });
}

// ── Whether the relay should run (restored on app launch and after boot) ────

export async function setServiceEnabled(enabled: boolean): Promise<void> {
  await AsyncStorage.setItem(ASYNC_KEY_SERVICE_ENABLED, enabled ? '1' : '0');
}

export async function isServiceEnabled(): Promise<boolean> {
  return (await AsyncStorage.getItem(ASYNC_KEY_SERVICE_ENABLED)) === '1';
}

export async function clearLogs(): Promise<void> {
  await AsyncStorage.removeItem(ASYNC_KEY_LOGS);
}

export function calculateStats(logs: LogEntry[]): RelayStats {
  const startOfDay = new Date();
  startOfDay.setHours(0, 0, 0, 0);
  const cutoff = startOfDay.getTime();

  let sentToday = 0;
  let failedToday = 0;

  for (const entry of logs) {
    if (entry.timestamp >= cutoff) {
      if (entry.status === 'sent' || entry.status === 'delivered') {
        sentToday++;
      } else if (entry.status === 'failed') {
        failedToday++;
      }
    }
  }

  return { sentToday, failedToday };
}

/**
 * Mask recipient phone number.
 * Never stores or reveals full OTP recipients.
 * Example: +254712345678 -> +2547•••••678
 */
export function maskPhoneNumber(phone: string): string {
  const cleaned = phone.replace(/[\s\-().]/g, '');
  if (cleaned.length <= 6) {
    return cleaned;
  }
  const prefixLength = Math.min(5, Math.floor(cleaned.length / 2));
  const suffixLength = 3;
  const prefix = cleaned.slice(0, prefixLength);
  const suffix = cleaned.slice(-suffixLength);
  const dots = '•'.repeat(Math.max(3, cleaned.length - prefixLength - suffixLength));
  return `${prefix}${dots}${suffix}`;
}
