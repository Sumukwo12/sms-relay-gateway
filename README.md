# SMS Phone Verification

Verify phone numbers with one-time SMS codes sent through a USB GSM modem, an Android phone gateway, or our dedicated SMS Relay companion app.

| Folder      | What it is                                                              |
| ----------- | ----------------------------------------------------------------------- |
| `backend/`  | Phoenix JSON API: code generation, storage, rate limiting, modem driver |
| `frontend/` | Next.js UI: enter phone → receive code → verify                         |
| `mobile/`   | React Native Android app (SMS Relay): sends verification SMS from SIM   |

## Quick start (no modem needed)

By default, dev and test use a **mock modem** that prints each SMS to the
backend console instead of sending it.

```sh
# 1. API on http://localhost:4000
cd backend
mix setup
mix phx.server

# 2. UI on http://localhost:3000 (second terminal)
cd frontend
npm install
npm run dev
```

Open http://localhost:3000, enter a number like `+254712345678`, then copy
the code from the backend log line `[Modem.Mock] SMS to ...`.

---

## Using your own Android phone (SMS Relay app)

Use your physical Android phone (e.g. personal Kenyan SIM card) to send real verification SMS.
The **phone connects out to the backend** over a secure WebSocket Phoenix Channel (`gateway:phone` at `/phone/websocket`), so the backend can run anywhere (cloud, VPS, or LAN) and the phone can use mobile data or Wi-Fi without needing a public IP or port forwarding.

### Architecture

```
Next.js (Web) → Phoenix API → Backend.Modem.Phone (GenServer)
                                    │  Phoenix Channel "gateway:phone" over WSS
                                    ▼
                         React Native (Foreground Service)
                                    │  Android SmsManager (native Kotlin module)
                                    ▼
                                SIM Card → Recipient
```

### 1. Configure the Backend

Set the adapter to `phone` and define a secret gateway authentication token:

```sh
cd backend
export MODEM_ADAPTER=phone
export PHONE_GATEWAY_TOKEN="your-secure-random-token-here"
mix phx.server
```

### 2. Build and Install the Mobile App

Compile and sideload the release APK to your phone (**requires Android SDK and JDK 17 — not newer**, e.g. JDK 21+ is not supported):

```sh
cd mobile
npm install
npx expo prebuild --platform android --clean
cd android && ./gradlew assembleRelease

# Install directly to phone via USB (with ADB debugging enabled)
adb install -r app/build/outputs/apk/release/app-release.apk
```

*(See [`mobile/README.md`](mobile/README.md) for full prerequisites and manual transfer instructions).*

### 3. Connect the Phone to the Backend

1. Open **SMS Relay** on the Android device.
2. Grant the required permissions (**SMS**, **Phone State**, **Notifications**).
3. In the **Setup** tab:
   - **WebSocket URL**:
     - Local LAN testing: `ws://192.168.1.X:4000/phone/websocket`
     - Production: `wss://api.yourdomain.com/phone/websocket`
   - **Gateway Token**: Enter the matching `PHONE_GATEWAY_TOKEN`.
   - **SIM Card**: Select your active SIM slot.
4. Tap **Test Connection** to confirm connectivity, then **Save Settings**.
5. In the **Dashboard** tab, flip the service toggle to **ON**.
   - A persistent foreground notification `SMS Relay Active: Connected · 0 sent today` will appear.
6. Verify status on the server:
   ```sh
   curl http://localhost:4000/api/modem/status
   # {"ready":true,"status":"ready"}
   ```
7. Enter a phone number on the Next.js website (http://localhost:3000). The phone will silently transmit the verification text using its SIM card.

---

## Using a real USB GSM modem

The real driver uses `circuits_uart`, which compiles a small C program, so
you need `make` and `gcc` on the PATH (on Windows, e.g. MSYS2 with
`mingw-w64-x86_64-gcc` and `make`). Then:

```sh
cd backend
export MODEM_ADAPTER=uart   # PowerShell: $env:MODEM_ADAPTER="uart"
export MODEM_PORT=COM3      # or /dev/ttyUSB0 on Linux
mix deps.get
mix phx.server
```

The modem is opened in SMS text mode (`AT+CMGF=1`). If the port is missing
or the device is unplugged, the API reports `modem_disconnected` and keeps
trying to reconnect every 10 seconds. Production builds (`MIX_ENV=prod`)
default to the real modem.

---

## Configuration (backend environment variables)

| Variable              | Default                   | Meaning                                                         |
| --------------------- | ------------------------- | --------------------------------------------------------------- |
| `MODEM_ADAPTER`       | `mock` (dev), `uart` prod | `mock`, `uart`, `android`, or `phone`                           |
| `PHONE_GATEWAY_TOKEN` | –                         | Required when `MODEM_ADAPTER=phone`. Secret auth token for app |
| `MODEM_PORT`          | `COM3`                    | Serial port of the USB modem (when `MODEM_ADAPTER=uart`)        |
| `MODEM_BAUD`          | `9600`                    | Serial baud rate                                                |
| `CODE_TTL_SECONDS`    | `300`                     | How long a code stays valid                                     |
| `CODE_LENGTH`         | `6`                       | Digits per code                                                 |
| `RATE_LIMIT_PER_HOUR`         | `3`                       | Codes per phone number per rolling hour                         |
| `RATE_LIMIT_PER_IP_PER_HOUR`  | `5`                       | Codes per client IP per rolling hour                            |
| `RATE_LIMIT_GLOBAL_PER_HOUR`  | `100`                     | Total codes allowed globally across all clients per hour        |
| `TRUST_PROXY`                 | `false`                   | Set to `true` to honour right-most `X-Forwarded-For` client IP  |
| `MAX_VERIFY_ATTEMPTS`         | `5`                       | Wrong guesses before the code is discarded                      |
| `SMS_TEMPLATE`                | see `config/config.exs`   | SMS body; `%{code}` is replaced with the code                   |
| `FRONTEND_ORIGIN`             | `http://localhost:3000`   | Comma-separated origins allowed by CORS                         |
| `PORT`                        | `4000`                    | HTTP port                                                       |
| `API_KEYS`                    | –                         | `/v1` keys, one per system: `billing:key1,crm:key2` (keys ≥ 16 chars) |
| `PUBLIC_API`                  | `true`                    | `false` disables the unauthenticated `/api/send-code` + `/api/verify-code` |
| `DAILY_SEND_LIMIT`            | `500`                     | Max SMS sent from the outbox per rolling 24h (protects your bundle) |
| `MESSAGE_MAX_ATTEMPTS`        | `3`                       | Send attempts per queued message before it is marked `failed`   |
| `MESSAGE_TTL_SECONDS`         | `86400`                   | How long a notification may wait in the queue (OTPs expire with their code) |
| `DATABASE_PATH`               | `backend_dev.db` (dev)    | SQLite file for the outbox. **Required in prod**                |

Frontend: `NEXT_PUBLIC_API_URL` (default `http://localhost:4000`), set at
build time. See `frontend/.env.example`.

## Integration API (`/v1`) — for your own systems

Your other systems send verification codes and notifications through the
`/v1` API. Each system gets its own key in `API_KEYS` and sends it as
`Authorization: Bearer <key>` (or `X-Api-Key: <key>`). Generate a key with
`mix phx.gen.secret 32`.

Messages are stored in an SQLite outbox and sent **one at a time** through
the modem/phone. If the phone is offline they wait in the queue and go out
as soon as it reconnects; failed sends are retried with backoff (15s, 30s,
60s…). Restarts don't lose queued messages.

| Method & path            | Body                                                | Success |
| ------------------------ | --------------------------------------------------- | ------- |
| `POST /v1/messages`      | `{"to", "body", "reference"?, "callback_url"?}`     | `202 {success, message}` |
| `GET /v1/messages/:id`   | –                                                   | `200 {success, message}` |
| `POST /v1/otp/send`      | `{"phone", "reference"?, "callback_url"?}`          | `202 {success, message, expires_in_seconds}` |
| `POST /v1/otp/verify`    | `{"phone", "code"}`                                 | `200 {success: true, verified: true}` |
| `GET /v1/status`         | –                                                   | `200 {modem: {status, ready, device}, queue: {pending, sent_last_24h, daily_limit}}` |

`body` is at most 480 characters (3 SMS parts). A `message` looks like:

```json
{
  "id": "msg_90ec3f69c57ba1862a1a", "kind": "notification", "to": "+254712345678",
  "status": "sent", "attempts": 1, "error": null, "reference": "order-7",
  "created_at": "...", "sent_at": "...", "delivered_at": null, "failed_at": null, "expires_at": "..."
}
```

`status` goes `queued → sending → sent → delivered`, or ends in `failed`
(`error` says why: e.g. `expired`, or the phone's send error). `delivered`
needs the carrier to return a delivery report, which not every network does.
Message bodies are never returned, and OTP bodies are erased once sent.

Example:

```sh
curl -X POST https://sms.example.com/v1/messages \
  -H "Authorization: Bearer $SMS_API_KEY" -H "Content-Type: application/json" \
  -d '{"to": "+254712345678", "body": "Your order #7 has shipped", "reference": "order-7"}'
```

**Webhooks.** With `callback_url`, the gateway POSTs
`{"event": "message.sent" | "message.delivered" | "message.failed", "message": {...}}`
on each status change. Verify it with the `X-Signature` header:
`sha256=` + hex HMAC-SHA256 of the raw request body, keyed with your API key.

Errors: `401 unauthorized`, `404 not_found`, `422 invalid_request (+field)`,
`429 rate_limited | daily_limit_reached | too_many_attempts`.

## Demo API (`/api`, used by the Next.js frontend)

These endpoints need no key, so turn them off with `PUBLIC_API=false` once the
backend is public and only your systems should trigger SMS.

| Method & path                | Body                     | Success                                         |
| ---------------------------- | ------------------------ | ----------------------------------------------- |
| `POST /api/send-code`        | `{"phone": "+2547..."}`  | `200 {success, expires_in_seconds}`             |
| `POST /api/verify-code`      | `{"phone", "code"}`      | `200 {success: true, verified: true}`           |
| `GET /api/modem/status`      | –                        | `200 {status: "ready"\|"disconnected", ready}`  |
| `GET /api/rate-limit/:phone` | – (URL-encode the `+`)   | `200 {remaining, limit, retry_after_seconds}`   |

Errors return `{success: false, error: "<code>", message}` with status:
`400 missing_phone|missing_params`, `422 invalid_phone|invalid_code|expired_or_missing`,
`429 rate_limited (+retry_after_seconds)|too_many_attempts`,
`502 modem_error`, `503 modem_disconnected`.

Phone numbers must be E.164 (`+` and country code); spaces, dashes and
parentheses are stripped.

## Tests

```sh
# Backend tests and precommit verification
cd backend && mix precommit

# Mobile type checks and linting
cd mobile && npm run lint && npx tsc --noEmit
```
