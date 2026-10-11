import { EventEmitter, type EventSubscription, requireNativeModule } from 'expo-modules-core';

export interface SimCard {
  subscriptionId: number;
  displayName: string;
  carrierName: string;
  slotIndex: number;
  number?: string;
}

export interface SmsResult {
  status: 'sent' | 'failed';
  error?: string;
}

export interface DeliveredEvent {
  id: string;
}

export interface DeviceInfo {
  battery: number | null;
  isCharging: boolean;
  signal: number | null;
}

export type { EventSubscription };

let SmsSenderNative: any = null;
let emitter: any = null;

try {
  SmsSenderNative = requireNativeModule('SmsSender');
  if (SmsSenderNative) {
    emitter = new EventEmitter(SmsSenderNative);
  }
} catch (err) {
  // Graceful fallback for non-native environments
  console.warn('[sms-sender] Native module not linked yet:', err);
}

export async function getSimCards(): Promise<SimCard[]> {
  if (!SmsSenderNative?.getSimCards) {
    return [];
  }
  return await SmsSenderNative.getSimCards();
}

export async function getDeviceInfo(): Promise<DeviceInfo> {
  if (!SmsSenderNative?.getDeviceInfo) {
    return { battery: null, isCharging: false, signal: null };
  }
  return await SmsSenderNative.getDeviceInfo();
}

export async function sendSms(
  to: string,
  body: string,
  subId?: number,
  id?: string
): Promise<SmsResult> {
  if (!SmsSenderNative?.sendSms) {
    return {
      status: 'failed',
      error: 'Native SMS module is not available on this platform',
    };
  }
  return await SmsSenderNative.sendSms(to, body, subId ?? null, id ?? null);
}

export function addDeliveryListener(listener: (event: DeliveredEvent) => void): EventSubscription | null {
  if (!emitter || typeof emitter.addListener !== 'function') {
    return null;
  }
  return emitter.addListener('onDelivered', listener);
}

export default {
  getSimCards,
  getDeviceInfo,
  sendSms,
  addDeliveryListener,
};
