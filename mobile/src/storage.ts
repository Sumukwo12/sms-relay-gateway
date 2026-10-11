import * as SecureStore from 'expo-secure-store';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { LogEntry, RelaySettings, RelayStats } from './types';

const SECURE_KEY_URL = 'sms_relay_server_url';
const SECURE_KEY_TOKEN = 'sms_relay_auth_token';
const ASYNC_KEY_SUB_ID = '@sms_relay_sub_id';
const ASYNC_KEY_LOGS = '@sms_relay_message_logs_v1';
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
