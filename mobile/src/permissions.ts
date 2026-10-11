import { PermissionsAndroid, Platform, Linking } from 'react-native';

export interface PermissionStatus {
  allGranted: boolean;
  sendSms: boolean;
  readPhoneState: boolean;
  postNotifications: boolean;
  missingPermissions: string[];
}

export async function checkPermissions(): Promise<PermissionStatus> {
  if (Platform.OS !== 'android') {
    return {
      allGranted: true,
      sendSms: true,
      readPhoneState: true,
      postNotifications: true,
      missingPermissions: [],
    };
  }

  const sendSms = await PermissionsAndroid.check(PermissionsAndroid.PERMISSIONS.SEND_SMS);
  const readPhoneState = await PermissionsAndroid.check(PermissionsAndroid.PERMISSIONS.READ_PHONE_STATE);

  let postNotifications = true;
  if (Platform.Version >= 33) {
    postNotifications = await PermissionsAndroid.check(
      PermissionsAndroid.PERMISSIONS.POST_NOTIFICATIONS
    );
  }

  const missing: string[] = [];
  if (!sendSms) missing.push('SEND_SMS (required to dispatch verification SMS)');
  if (!readPhoneState) missing.push('READ_PHONE_STATE (required to list SIM cards)');
  if (!postNotifications) missing.push('POST_NOTIFICATIONS (required for persistent service status)');

  return {
    allGranted: sendSms && readPhoneState && postNotifications,
    sendSms,
    readPhoneState,
    postNotifications,
    missingPermissions: missing,
  };
}

export async function requestAllPermissions(): Promise<PermissionStatus> {
  if (Platform.OS !== 'android') {
    return checkPermissions();
  }

  const permissionsToRequest: any[] = [
    PermissionsAndroid.PERMISSIONS.SEND_SMS,
    PermissionsAndroid.PERMISSIONS.READ_PHONE_STATE,
  ];

  if (Platform.Version >= 33) {
    permissionsToRequest.push(PermissionsAndroid.PERMISSIONS.POST_NOTIFICATIONS);
  }

  try {
    const results = await PermissionsAndroid.requestMultiple(permissionsToRequest);

    const sendSms = results[PermissionsAndroid.PERMISSIONS.SEND_SMS] === PermissionsAndroid.RESULTS.GRANTED;
    const readPhoneState = results[PermissionsAndroid.PERMISSIONS.READ_PHONE_STATE] === PermissionsAndroid.RESULTS.GRANTED;
    const postNotifications = Platform.Version >= 33
      ? results[PermissionsAndroid.PERMISSIONS.POST_NOTIFICATIONS] === PermissionsAndroid.RESULTS.GRANTED
      : true;

    const missing: string[] = [];
    if (!sendSms) missing.push('SEND_SMS (required to dispatch verification SMS)');
    if (!readPhoneState) missing.push('READ_PHONE_STATE (required to list SIM cards)');
    if (!postNotifications) missing.push('POST_NOTIFICATIONS (required for persistent service status)');

    return {
      allGranted: sendSms && readPhoneState && postNotifications,
      sendSms,
      readPhoneState,
      postNotifications,
      missingPermissions: missing,
    };
  } catch (err) {
    console.error('[Permissions] Error requesting permissions:', err);
    return checkPermissions();
  }
}

export function openAppSettings() {
  Linking.openSettings().catch(() => {});
}
