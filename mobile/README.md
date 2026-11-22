# SMS Relay (Android Mobile App)

SMS Relay is an Android companion app built with React Native and Expo that connects directly to the Phoenix backend over a WebSocket Phoenix Channel (`gateway:phone`). It silently transmits OTP SMS verification codes via the phone's physical SIM card (such as a Kenyan Safaricom / Airtel SIM) using native Android APIs.

---

## 1. Prerequisites

Before developing or compiling the application:

- **Node.js**: v18.x or later (recommended: Node 20 or 22)
- **JDK**: Java Development Kit 17 (**JDK 17 required; newer versions like JDK 21+ are not supported** by the Gradle/React Native toolchain)
- **Android SDK**: Android SDK Command-Line Tools & Platform 34 or 35
  - Set `ANDROID_HOME` or `ANDROID_SDK_ROOT` in your environment (e.g., `export ANDROID_HOME=$HOME/Android/Sdk`)
  - Ensure `platform-tools` (`adb`) is on your `$PATH`
- **Physical Android Phone**: Running Android 8.0+ (API 26+) with an active SIM card and SMS airtime/SMS bundle.

> **Note on Expo Go**: Expo Go cannot be used because silent background SMS dispatch and foreground service require native Android modules (`SmsManager`, `SubscriptionManager`, Notifee). Use an Expo development build or sideload the release APK.

---

## 2. Development Run

To test and run the app with live reload connected to a physical device or emulator via USB debugging:

```sh
cd mobile
npm install

# Run on connected Android device
npx expo run:android
```

---

## 3. Building the Release APK

The app is designed for **sideloading** (Google Play restricts apps using the `SEND_SMS` permission). 

### Release Keystore Configuration

To sign the release build with your own release keystore:

1. Generate a keystore with `keytool`:

```sh
keytool -genkeypair -v -keystore ~/smsrelay-release.keystore -alias smsrelay-key -keyalg RSA -keysize 2048 -validity 10000
```

2. Add your keystore credentials to `~/.gradle/gradle.properties`:

```properties
SMSRELAY_UPLOAD_STORE_FILE=/home/user/smsrelay-release.keystore
SMSRELAY_UPLOAD_STORE_PASSWORD=your_keystore_password
SMSRELAY_UPLOAD_KEY_ALIAS=smsrelay-key
SMSRELAY_UPLOAD_KEY_PASSWORD=your_key_password
```

> **Fallback**: If these properties are not defined, the Gradle build will automatically fall back to signing with the default debug keystore and log a build warning. **Never commit keystores or passwords to git.**

### Build Command

```sh
cd mobile

# 1. Generate / sync the native Android project
npx expo prebuild --platform android --clean

# 2. Build the release APK
cd android
./gradlew assembleRelease
```

### Where the APK Lands

The resulting APK will be generated at:
```
mobile/android/app/build/outputs/apk/release/app-release.apk
```

---

## 4. Installing on the Phone

Connect your Android phone via USB (with **USB Debugging** enabled under Developer Options) and run:

```sh
adb install -r android/app/build/outputs/apk/release/app-release.apk
```

Alternatively, you can copy `app-release.apk` to your phone via USB file transfer, Google Drive, WhatsApp, or local file server, tap the APK in your phone's file manager, and choose **Install** (enabling *"Install from unknown sources"* if prompted).

---

## 5. First-Time Setup

1. **Open SMS Relay** on the phone.
2. **Grant Permissions**:
   - `SEND_SMS`: Allows the app to dispatch verification texts.
   - `READ_PHONE_STATE`: Allows detecting available SIM cards for dual-SIM devices.
   - `POST_NOTIFICATIONS`: Keeps the persistent foreground service alive.
3. **Configure Connection** in the **Setup** tab:
   - **WebSocket URL**:
     - Local development: `ws://192.168.1.X:4000/phone/websocket` (replace with your server machine's LAN IP).
     - Production / Cloud: `wss://api.yourdomain.com/phone/websocket`.
   - **Gateway Token**: Enter the secret token that matches `PHONE_GATEWAY_TOKEN` set in your backend environment.
   - **SIM Card**: Select SIM 1 or SIM 2.
4. **Test Connection**: Tap **Test Connection**. A green badge should confirm successful handshake and Phoenix Channel join.
5. Tap **Save Settings**.
6. Switch to the **Dashboard** tab and toggle the **Service Switch** to **ON**.
   - A persistent notification `SMS Relay Active: Connected · 0 sent today` will appear in the Android notification drawer.
7. Test sending an SMS using the **Send Test SMS** card on the Dashboard.

---

## 6. Battery Optimization Tips by Brand

To ensure the relay stays connected 24/7 without being killed when the screen turns off or the phone is left idle overnight, exempt SMS Relay from battery management:

### Samsung (One UI)
- Go to **Settings** → **Apps** → **SMS Relay** → **Battery** → Select **Unrestricted**.
- Go to **Settings** → **Battery and device care** → **Battery** → **Background usage limits** → Add **SMS Relay** to **Never sleeping apps**.

### Tecno / Infinix (HiOS / XOS)
- Go to **Settings** → **Apps & notifications** → **App management** → **SMS Relay**.
- Tap **Battery** → **Battery optimization** → Switch from "Optimized" to **Don't optimize**.
- Open **Phone Master** app → **Auto-start management** → Enable **SMS Relay**.
- Open recent apps screen, pull down on the **SMS Relay** card and tap the **Lock** icon to prevent the system task killer from closing it.

### Xiaomi / Redmi / POCO (MIUI / HyperOS)
- Go to **Settings** → **Apps** → **Manage apps** → **SMS Relay**.
- Enable **Autostart**.
- Tap **Battery saver** → Select **No restrictions**.
- Go to **App permissions** → ensure **Send SMS messages** is set to **Always allow**.
- Lock the app in the recent apps overview.

---

## 7. Troubleshooting

### SMS Sending Fails
| Symptom / Error | Root Cause & Resolution |
| :--- | :--- |
| **Generic carrier failure** | Check that the SIM card has active airtime or an active SMS bundle. Prepaid SIMs without funds or with expired bundles cannot dispatch SMS. |
| **Radio turned off** | The phone is in **Airplane Mode** or cellular reception is toggled off. Turn off Airplane mode. |
| **No cellular network service** | The device has zero signal reception. Check carrier antenna bars. |
| **SEND_SMS permission not granted** | Open Android Settings → Apps → SMS Relay → Permissions → SMS → Select **Allow**. |
| **Dual SIM wrong slot** | If your phone has two SIMs, open the Setup tab and ensure the correct SIM slot with airtime is selected. |

### Connection Fails
| Symptom / Error | Root Cause & Resolution |
| :--- | :--- |
| **Invalid gateway token** | The token entered in the app does not match `PHONE_GATEWAY_TOKEN` on the backend. Check backend `.env` or system environment. |
| **Cannot reach server / timeout** | Ensure the phone can reach the backend IP. If testing locally over Wi-Fi, ensure your computer's firewall allows incoming connections on port `4000`. |
| **`ws://` vs `wss://`** | Use `ws://` only on private LAN IPs (`192.168.x.x`, `10.x.x.x`). Use `wss://` for any public domain with a valid SSL/TLS certificate. |
| **Disconnected when screen turns off** | The app was put to sleep by Android Doze. Follow the battery optimization instructions in Section 6 and grant the foreground service notification permission. |
