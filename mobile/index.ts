import { registerRootComponent } from 'expo';
import { AppRegistry } from 'react-native';
import notifee from '@notifee/react-native';

import App from './App';
import { relayManager } from './src/relayManager';

// Call notifee.registerForegroundService exactly once at app startup
notifee.registerForegroundService(() => {
  return new Promise(() => {
    // Keeps running indefinitely in background until stopForegroundService() is called
  });
});

// Started by the native boot receiver (sms-sender module) after the phone
// reboots or the app is updated, when the relay was on before.
AppRegistry.registerHeadlessTask('SmsRelayBoot', () => async () => {
  await relayManager.initialize();
  await relayManager.resumeIfEnabled();
});

registerRootComponent(App);
