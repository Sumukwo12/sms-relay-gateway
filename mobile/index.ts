import { registerRootComponent } from 'expo';
import notifee from '@notifee/react-native';

import App from './App';

// Call notifee.registerForegroundService exactly once at app startup
notifee.registerForegroundService(() => {
  return new Promise(() => {
    // Keeps running indefinitely in background until stopForegroundService() is called
  });
});

registerRootComponent(App);
