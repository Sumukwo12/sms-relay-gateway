const { withAndroidManifest } = require('@expo/config-plugins');

module.exports = function withAndroidForegroundService(config) {
  return withAndroidManifest(config, (config) => {
    const mainApplication = config.modResults.manifest.application?.[0];
    if (!mainApplication) return config;

    if (!mainApplication.service) {
      mainApplication.service = [];
    }

    // Configure Notifee ForegroundService with specialUse foregroundServiceType
    const notifeeServiceName = 'app.notifee.core.ForegroundService';
    let service = mainApplication.service.find(
      (s) => s.$?.['android:name'] === notifeeServiceName
    );

    if (!service) {
      service = {
        $: {
          'android:name': notifeeServiceName,
          'android:foregroundServiceType': 'specialUse',
          'tools:replace': 'android:foregroundServiceType',
        },
      };
      mainApplication.service.push(service);
    } else {
      service.$['android:foregroundServiceType'] = 'specialUse';
      service.$['tools:replace'] = 'android:foregroundServiceType';
    }

    // Add property child element for specialUse FGS subtype
    if (!service.property) {
      service.property = [];
    }
    const propName = 'android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE';
    const propValue = "Relays one-time verification SMS from the user's own server";
    let prop = service.property.find((p) => p.$?.['android:name'] === propName);
    if (!prop) {
      service.property.push({
        $: {
          'android:name': propName,
          'android:value': propValue,
        },
      });
    } else {
      prop.$['android:value'] = propValue;
    }

    // Add tools namespace if not present
    if (!config.modResults.manifest.$['xmlns:tools']) {
      config.modResults.manifest.$['xmlns:tools'] = 'http://schemas.android.com/tools';
    }

    return config;
  });
};
