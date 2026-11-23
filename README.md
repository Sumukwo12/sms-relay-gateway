# SMS Relay Gateway

**Turn an Android phone into your own SMS gateway.** Send OTP verification
codes and SMS notifications from your website or app through a phone and SIM
you already own, instead of paying a provider like Twilio for every message.

| | |
| --- | --- |
| 🌐 **Live site** | [sms.strand.co.ke](https://sms.strand.co.ke) |
| 📱 **Android app** | [Download SMS Relay 1.2.0 (APK, 71 MB)](https://sms.strand.co.ke/downloads/sms-relay.apk) · also in this repo: [`frontend/public/downloads/sms-relay.apk`](frontend/public/downloads/sms-relay.apk) |
| 📘 **API spec** | [OpenAPI 3.1 (`/openapi.json`)](https://sms.strand.co.ke/openapi.json), importable into Postman |
| 🧪 **Try it** | [Interactive demo](https://sms.strand.co.ke/#simulation) · [Postman guide](https://sms.strand.co.ke/#postman) |
| 🧑‍💻 **Source** | [github.com/Sumukwo12/sms-phone-verification](https://github.com/Sumukwo12/sms-phone-verification) |

## How it works

```
Your website ──► your backend ──► SMS Relay Gateway ──► your Android phone ──► SMS
                 (holds the API key)    (this server)      (SMS Relay app + SIM)
```

1. **Create an account** at [/register](https://sms.strand.co.ke/register) or
   in the app. An administrator approves new accounts.
2. **Install the app** ([APK](https://sms.strand.co.ke/downloads/sms-relay.apk))
   on an Android 7+ phone with a SIM and sign in. The phone becomes your gateway.
3. **Create an API key** in the dashboard. Start with a **test key**
   (`sk_test_…`): nothing is sent and OTP codes come back in the response.
4. **Call the API from your backend**: `POST /v1/otp/send` and
   `POST /v1/otp/verify` for phone verification, `POST /v1/messages` for any
   SMS. Swap in a live key (`sk_…`) when it works.

```sh
curl -X POST https://sms.strand.co.ke/v1/otp/send \
  -H "Authorization: Bearer sk_test_…" \
  -H "Content-Type: application/json" \
  -d '{"phone": "0712345678"}'
```

Keep API keys on your server (e.g. in `.env`), never in browser JavaScript
or a mobile app: anyone with a key can send SMS through your phone.

### Installing the app

Android blocks SMS access for apps installed from outside the Play Store
until you allow it: **Settings → Apps → SMS Relay → ⋮ → Allow restricted
settings**, then grant SMS permission. On Xiaomi, Redmi and Samsung phones
also turn on **Autostart** and set battery to **No restrictions**, or the
phone may stop relaying in the background. Android may ask to allow "a large
number of messages" after about 30 SMS in 30 minutes.

## What's in this repository

| Folder      | What it is                                                                       |
| ----------- | -------------------------------------------------------------------------------- |
| `backend/`  | Phoenix JSON API: accounts, API keys, OTP codes, queue, routing to users' phones |
| `frontend/` | Next.js site: home page, sign-up, user dashboard, admin panel, integration docs  |
| `mobile/`   | React Native Android app (SMS Relay): signs in and sends the SMS from its SIM     |

Nothing works without signing in: the website shows only the home page,
sign-in and sign-up to visitors, and the app shows only a welcome screen.

## Accounts at a glance

1. **The admin** is set on the server: `ADMIN_EMAIL` and `ADMIN_PASSWORD` in
   the server's environment create (or promote) that account when the server starts.
   Nobody can register as an admin. The admin panel is at `/admin`: system
   overview, users (approve, suspend, limits, make admin), all phones and all
   messages.
2. **Sign up** on the website (`/register`) or in the app. Every new account
   is a **pending** user until the admin approves it.
3. **Link a phone**: install SMS Relay, tap **Sign in** and use the same email
   and password. The phone gets its own device token and shows up on
   `/dashboard/phones`.
4. **Create an API key** on `/dashboard/keys` and call `/v1` (see
   `/dashboard/docs`, or [Integration API](#integration-api-v1--for-your-own-systems)).
   Each user's messages go only through their own phones (the most recently
   connected one, or the `device_id` they pass) and count against their own
   daily limit (`USER_DAILY_SEND_LIMIT`, default 200; admins can change it
   per user). Webhooks are signed with the user's webhook secret.

Server-level `API_KEYS` from the environment still work: they send through
an admin's phone (or a phone using the old shared `PHONE_GATEWAY_TOKEN`).

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
3. In the **Account** tab, sign in (or create an account) with the server
   address (`https://sms.strand.co.ke`, or `http://192.168.1.X:4000` on a
   LAN), email and password. The relay connects and starts by itself.
   Pick the sending SIM in the **Setup** tab.

   **Or, the legacy shared token** (no account): open **Setup → Advanced:
   server token**:
   - **WebSocket URL**:
     - Local LAN testing: `ws://192.168.1.X:4000/phone`
     - Production: `wss://sms.strand.co.ke/phone`

     Leave off `/websocket`: the Phoenix client adds it. (App builds before
     the URL fix fail with "Cannot reach server" if it is included.)
   - **Gateway Token**: Enter the matching `PHONE_GATEWAY_TOKEN`
     (set in the server's environment).
   - **SIM Card**: Select your active SIM slot.
   - Tap **Test Connection** to confirm connectivity, then **Save Settings**.
4. In the **Dashboard** tab, check the service toggle is **ON**.
   - A persistent foreground notification `SMS Relay Active: Connected · 0 sent today` will appear.
   - The relay stays on: it resumes when the app is reopened and starts by
     itself after the phone reboots, until you switch it off. Delivery
     reports that arrive while the phone is offline are sent once it
     reconnects.
5. Verify status on the server (or on /dashboard/phones):
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
| `PHONE_GATEWAY_TOKEN` | –                         | Shared token for the legacy server phone (accounts don't need it) |
| `ADMIN_EMAIL` / `ADMIN_PASSWORD` | –             | The admin account, created or promoted at boot                  |
| `USER_DAILY_SEND_LIMIT` | `200`                   | SMS parts per user per rolling 24h (admins can override per user) |
| `DEFAULT_COUNTRY_CODE` | `254`                     | Country code added to local numbers like `0712345678`           |
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
| `PUBLIC_API`                  | `true` dev, `false` prod  | Enables the unauthenticated demo `/api/*` endpoints             |
| `DAILY_SEND_LIMIT`            | `500`                     | Max **SMS parts** sent per rolling 24h, all paths (protects your bundle) |
| `MESSAGE_MAX_SEGMENTS`        | `4`                       | Max SMS parts per message                                       |
| `MESSAGE_MAX_ATTEMPTS`        | `3`                       | Send attempts per queued message before it is marked `failed`   |
| `MESSAGE_TTL_SECONDS`         | `86400`                   | How long a notification may wait in the queue (OTPs expire with their code) |
| `MESSAGE_RETENTION_DAYS`      | `30`                      | Finished messages and webhook records are deleted after this (min 2) |
| `WEBHOOK_MAX_ATTEMPTS`        | `12`                      | Tries per webhook (backoff 30s → 1h, about 4h in total)         |
| `ALERT_WEBHOOK_URL`           | –                         | Where alerts are POSTed (Slack/Discord incoming webhook, or any JSON endpoint) |
| `ALERT_OFFLINE_SECONDS`       | `300`                     | Alert when the phone/modem has been offline this long           |
| `ALERT_QUEUE_AGE_SECONDS`     | `600`                     | Alert when a message has waited this long                       |
| `ALERT_BATTERY_PERCENT`       | `20`                      | Alert when the relay phone is below this and not charging       |
| `DATABASE_PATH`               | `backend_dev.db` (dev)    | SQLite file (outbox, codes, webhooks). **Required in prod**     |

Frontend: `NEXT_PUBLIC_API_URL` (default `http://localhost:4000`), set at
build time. See `frontend/.env.example`.

## Integration API (`/v1`) — for your own systems

Your other systems send verification codes and notifications through the
`/v1` API, with an API key sent as `Authorization: Bearer <key>` (or
`X-Api-Key: <key>`). Users create keys in the dashboard (`/dashboard/keys`);
server-level keys can still be set in `API_KEYS` (`mix phx.gen.secret 32`).
The full contract is in [`frontend/public/openapi.json`](frontend/public/openapi.json),
served at `/openapi.json`, and the dashboard's Integration docs page has
curl/PHP/Node.js/Python examples.

- **Test keys** (`sk_test_…`) simulate everything: messages go straight to
  `delivered`, webhooks fire, nothing reaches a phone or counts against
  limits, and `/v1/otp/send` returns the code as `test_code`.
- **Local numbers** (`0712345678`, `712345678`) get `DEFAULT_COUNTRY_CODE`
  (default `254`).
- **OTP options**: `template` (with `{code}` and optional `{minutes}`),
  `code_length` (4–8) and `expires_in` (60–3600 s); each account can set a
  default template.
- **Account webhook URL** (dashboard Settings) receives `message.*` events
  for messages without a `callback_url`, plus `device.connected` /
  `device.disconnected`.

Messages are stored in an SQLite outbox and sent **one at a time** through
the modem/phone. If the phone is offline they wait in the queue and go out
as soon as it reconnects; failed sends are retried with backoff (15s, 30s,
60s…). Restarts don't lose queued messages, verification codes or
pending webhooks.

| Method & path            | Body                                                | Success |
| ------------------------ | --------------------------------------------------- | ------- |
| `POST /v1/messages`      | `{"to", "body", "reference"?, "callback_url"?}`     | `202 {success, message}` |
| `GET /v1/messages/:id`   | –                                                   | `200 {success, message}` |
| `POST /v1/otp/send`      | `{"phone", "reference"?, "callback_url"?}`          | `202 {success, message, expires_in_seconds}` |
| `POST /v1/otp/verify`    | `{"phone", "code"}`                                 | `200 {success: true, verified: true}` |
| `GET /v1/status`         | –                                                   | `200 {modem: {status, ready, device}, queue: {pending, sent_last_24h, daily_limit}, webhooks: {pending}, alerts: [{alert, message}]}` |

**Idempotency.** Send `Idempotency-Key: <unique id>` (or an
`idempotency_key` field) with `POST /v1/messages` and `POST /v1/otp/send`.
If you retry after a timeout or network error, the gateway answers
`200` with the message it already queued (header `Idempotent-Replayed: true`)
instead of sending a second SMS or a new code. Keys are per system, up to
100 characters, and remembered for `MESSAGE_RETENTION_DAYS`.

**OTP codes** belong to the system that requested them: a code sent through
the `billing` key can only be verified with the `billing` key.

**SMS parts.** `body` is at most 480 characters and `MESSAGE_MAX_SEGMENTS`
(default 4) SMS parts. Plain text fits 160 characters in one SMS and 153 per
part after that; a single emoji or non-Latin character switches the whole
message to 70 per SMS / 67 per part. `DAILY_SEND_LIMIT` and
`sent_last_24h` count parts, because that is what the bundle charges.
Each message reports its `segments`. A `message` looks like:

```json
{
  "id": "msg_90ec3f69c57ba1862a1a", "kind": "notification", "to": "+254712345678",
  "status": "sent", "attempts": 1, "error": null, "reference": "order-7", "segments": 1,
  "created_at": "...", "sent_at": "...", "delivered_at": null, "failed_at": null, "expires_at": "..."
}
```

`status` goes `queued → sending → sent → delivered`, or ends in `failed`
(`error` says why: e.g. `expired`, or the phone's send error). `delivered`
needs the carrier to return a delivery report, which not every network does.
Message bodies are never returned, and are erased once a message is sent,
delivered or failed.

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
Webhooks are stored and retried until your endpoint answers `2xx` (backoff
30s → 1h, `WEBHOOK_MAX_ATTEMPTS` tries; a `4xx` other than 408/429 is final),
and the events for one message always arrive in order.

Errors: `401 unauthorized`, `404 not_found`, `422 invalid_request (+field)`,
`429 rate_limited | daily_limit_reached | too_many_attempts`.

## Demo API (`/api`, used by the Next.js frontend)

These endpoints need no key, so they are **off in production** (`MIX_ENV=prod`)
unless `PUBLIC_API=true`. They still count toward `DAILY_SEND_LIMIT`.
For monitoring, use the authenticated `GET /v1/status`.

| Method & path                | Body                     | Success                                         |
| ---------------------------- | ------------------------ | ----------------------------------------------- |
| `POST /api/send-code`        | `{"phone": "+2547..."}`  | `200 {success, expires_in_seconds}`             |
| `POST /api/verify-code`      | `{"phone", "code"}`      | `200 {success: true, verified: true}`           |
| `GET /api/modem/status`      | –                        | `200 {status: "ready"\|"disconnected", ready}`  |
| `GET /api/rate-limit/:phone` | – (URL-encode the `+`)   | `200 {remaining, limit, retry_after_seconds}`   |

Errors return `{success: false, error: "<code>", message}` with status:
`400 missing_phone|missing_params`, `422 invalid_phone|invalid_code|expired_or_missing`,
`429 rate_limited (+retry_after_seconds)|too_many_attempts|daily_limit_reached`,
`502 modem_error`, `503 modem_disconnected`.

Phone numbers must be E.164 (`+` and country code); spaces, dashes and
parentheses are stripped.

## Alerts

The backend checks itself every minute and posts to `ALERT_WEBHOOK_URL` (and
the log) when an alert starts and when it clears:

| Alert              | When                                                        |
| ------------------ | ----------------------------------------------------------- |
| `modem_offline`    | Phone/modem not ready for `ALERT_OFFLINE_SECONDS`           |
| `queue_stuck`      | A message has waited `ALERT_QUEUE_AGE_SECONDS`              |
| `battery_low`      | Relay phone below `ALERT_BATTERY_PERCENT` and not charging  |
| `daily_limit_near` | 90% of `DAILY_SEND_LIMIT` used                              |

The body has `text` (Slack) and `content` (Discord) plus `alert`, `status`
(`firing`/`resolved`) and `message`. Firing alerts are also listed in
`GET /v1/status`.

## Deploying

CI builds two Docker images on every push and, for `main`, publishes them to
GitHub Container Registry: `ghcr.io/<owner>/sms-gateway` (the Phoenix API)
and `ghcr.io/<owner>/sms-frontend` (the website). Each is tagged with the
hash of its own folder, so a website-only change doesn't restart the backend.

To self-host, run both behind an HTTPS reverse proxy (the relay phone's
`wss://` connection needs TLS) on one hostname:

| Path                         | Goes to                   |
| ---------------------------- | ------------------------- |
| `/api`, `/v1`, `/phone`      | backend, port `4000`      |
| everything else              | website, port `3000`      |

Give the backend a persistent volume for its SQLite database
(`DATABASE_PATH`, e.g. `/data/gateway.db`; migrations run on boot) and the
environment from [Configuration](#configuration-backend-environment-variables):
at least `PHX_HOST`, `SECRET_KEY_BASE` (`mix phx.gen.secret`),
`MODEM_ADAPTER=phone`, `TRUST_PROXY=true` and `ADMIN_EMAIL` /
`ADMIN_PASSWORD`.

The production server's own deployment files (Compose file, proxy config,
deploy and backup scripts, `.env`) are kept on the server, not in this
repository. On `main`, the CI `deploy` job connects over SSH and runs
`$DEPLOY_PATH/deploy/deploy.sh <backend-image> <frontend-image>` there. It
needs these GitHub settings (Settings → Secrets and variables → Actions):
`VPS_HOST`, `VPS_USER`, `PHX_HOST`, optionally `VPS_PORT` and `DEPLOY_PATH`
(variables), and `VPS_SSH_KEY` and `VPS_KNOWN_HOSTS` (secrets of the
`production` environment).

## Tests

```sh
# Backend tests and precommit verification
cd backend && mix precommit

# Mobile type checks, linting and unit tests
cd mobile && npm run lint && npx tsc --noEmit && npm test

# Frontend linting and unit tests
cd frontend && npm run lint && npm test
```

CI (`.github/workflows/ci.yml`) runs all of these plus a Docker image build.
