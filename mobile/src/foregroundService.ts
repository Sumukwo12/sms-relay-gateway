import notifee, {
  AndroidImportance,
  AndroidForegroundServiceType,
} from '@notifee/react-native';
import { Platform } from 'react-native';

const NOTIFICATION_CHANNEL_ID = 'sms_relay_foreground_channel';
const NOTIFICATION_ID = 'sms_relay_persistent_notification';

let isChannelCreated = false;

export async function initForegroundService(): Promise<void> {
  if (Platform.OS !== 'android') return;

  if (!isChannelCreated) {
    await notifee.createChannel({
      id: NOTIFICATION_CHANNEL_ID,
      name: 'SMS Relay Background Service',
      description: 'Maintains connection to server for outgoing verification SMS delivery',
      importance: AndroidImportance.LOW,
      sound: undefined,
      vibration: false,
    });
    isChannelCreated = true;
  }
}

export async function updateForegroundNotification(statusText: string): Promise<void> {
  if (Platform.OS !== 'android') return;

  await initForegroundService();

  await notifee.displayNotification({
    id: NOTIFICATION_ID,
    title: 'SMS Relay Active',
    body: statusText,
    android: {
      channelId: NOTIFICATION_CHANNEL_ID,
      asForegroundService: true,
      // Special Use foreground service type (0x40000000) for Android 14/15+ sideloaded relay
      foregroundServiceTypes: [
        AndroidForegroundServiceType.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
      ],
      ongoing: true,
      autoCancel: false,
      color: '#607938',
      pressAction: {
        id: 'default',
      },
    },
  });
}

export async function stopForegroundService(): Promise<void> {
  if (Platform.OS !== 'android') return;

  try {
    await notifee.stopForegroundService();
    await notifee.cancelNotification(NOTIFICATION_ID);
  } catch (err) {
    console.warn('[ForegroundService] Error stopping foreground service:', err);
  }
}

export async function checkBatteryOptimization(): Promise<boolean> {
  if (Platform.OS !== 'android') return false;

  try {
    const isIgnoring = await notifee.isBatteryOptimizationEnabled();
    // In Notifee: isBatteryOptimizationEnabled() returns true if optimization is ENABLED (i.e. NOT exempted)
    return isIgnoring;
  } catch (err) {
    console.warn('[Battery] Error checking battery optimization:', err);
    return false;
  }
}

export async function requestBatteryOptimizationExemption(): Promise<void> {
  if (Platform.OS !== 'android') return;

  try {
    await notifee.openBatteryOptimizationSettings();
  } catch (err) {
    console.warn('[Battery] Error opening battery optimization settings:', err);
  }
}
