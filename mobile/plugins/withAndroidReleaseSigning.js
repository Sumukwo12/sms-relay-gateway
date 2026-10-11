const { withAppBuildGradle } = require('@expo/config-plugins');

module.exports = function withAndroidReleaseSigning(config) {
  return withAppBuildGradle(config, (config) => {
    let contents = config.modResults.contents;

    const releaseSigningBlock = `        release {
            if (project.hasProperty('SMSRELAY_UPLOAD_STORE_FILE')) {
                storeFile file(SMSRELAY_UPLOAD_STORE_FILE)
                storePassword SMSRELAY_UPLOAD_STORE_PASSWORD
                keyAlias SMSRELAY_UPLOAD_KEY_ALIAS
                keyPassword SMSRELAY_UPLOAD_KEY_PASSWORD
            } else {
                logger.warn("WARNING: SMSRELAY_UPLOAD_STORE_FILE not configured in gradle.properties. Falling back to debug keystore for signing.")
                storeFile file('debug.keystore')
                storePassword 'android'
                keyAlias 'androiddebugkey'
                keyPassword 'android'
            }
        }`;

    if (!contents.includes('SMSRELAY_UPLOAD_STORE_FILE')) {
      contents = contents.replace(
        '    signingConfigs {\n        debug {',
        `    signingConfigs {\n${releaseSigningBlock}\n        debug {`
      );
    }

    const defaultReleaseBlock = '// see https://reactnative.dev/docs/signed-apk-android.\n            signingConfig signingConfigs.debug';
    const newReleaseBlock = '// see https://reactnative.dev/docs/signed-apk-android.\n            signingConfig signingConfigs.release';
    if (contents.includes(defaultReleaseBlock)) {
      contents = contents.replace(defaultReleaseBlock, newReleaseBlock);
    }

    config.modResults.contents = contents;
    return config;
  });
};
