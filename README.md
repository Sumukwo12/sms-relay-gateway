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
     - Production: `wss://sms.strand.co.ke/phone/websocket`
   - **Gateway Token**: Enter the matching `PHONE_GATEWAY_TOKEN`.
   - **SIM Card**: Select your active SIM slot.
4. Tap **Test Connection** to confirm connectivity, then **Save Settings**.
5. In the **Dashboard** tab, flip the service toggle to **ON**.
   - A persistent foreground notification `SMS Relay Active: Connected · 0 sent today` will appear.
   - The relay stays on: it resumes when the app is reopened and starts by
     itself after the phone reboots, until you switch it off. Delivery
     reports that arrive while the phone is offline are sent once it
     reconnects.
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
`/v1` API. Each system gets its own key in `API_KEYS` and sends it as
`Authorization: Bearer <key>` (or `X-Api-Key: <key>`). Generate a key with
`mix phx.gen.secret 32`.

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

`deploy/` runs the backend as a Docker container behind an HTTPS reverse
proxy, which the relay phone's `wss://` connection needs. The backend joins
the Docker network named by `PROXY_NETWORK` as `sms-gateway`, so an existing
proxy container on that network serves it with `reverse_proxy
sms-gateway:4000`. On a server with no proxy, `COMPOSE_PROFILES=standalone`
also runs the bundled Caddy on ports 80/443:

```sh
cd deploy
cp .env.example .env      # set PHX_HOST, SECRET_KEY_BASE, API_KEYS, PHONE_GATEWAY_TOKEN…
echo COMPOSE_PROFILES=standalone >> .env   # only without an existing proxy
docker network create sms-gateway-proxy    # the default PROXY_NETWORK
docker compose up -d --build
```

The SQLite database lives in the `gateway-data` volume and migrations run on
boot. Back it up nightly with `deploy/backup.sh` from cron (instructions in
the script). For a USB modem, uncomment `devices:` in `docker-compose.yml`.

### Continuous deployment to a VPS

Every push to `main` that passes CI is deployed automatically:

1. CI builds the backend image and pushes it to
   `ghcr.io/<owner>/sms-gateway:<commit-sha>`.
2. The `deploy` job copies `deploy/` to the VPS over SSH and runs
   `deploy/deploy.sh <image>` there.
3. `deploy.sh` refuses a half-filled `.env` (empty or example values), backs
   up the database, starts the new image, and waits until
   `https://$PHX_HOST/v1/status` answers. If it doesn't within 3 minutes, it
   rolls back to the previous image and the job fails.

**One-time VPS setup** (Ubuntu/Debian, x86-64). Point the hostname's DNS A
record at the server, generate the CI key pair on your PC
(`ssh-keygen -t ed25519 -N "" -f deploy_key`), then run
[`deploy/server-setup.sh`](deploy/server-setup.sh) on the server as root:

```sh
APP_HOST=sms.strand.co.ke DEPLOY_PATH=/apps/sms-gateway \
DEPLOY_KEY='<contents of deploy_key.pub>' bash server-setup.sh
```

It installs Docker if needed, creates the `deploy` user (SSH key only) and
`.env` with fresh secrets (never overwriting an existing one). If a Caddy
container already serves port 443, it adds the site to that Caddyfile
(backed up, validated, restored on failure) and joins its network; otherwise
it enables the bundled Caddy. Optionally add the nightly `backup.sh` cron
line from that script.

**GitHub settings** (Settings → Secrets and variables → Actions):

| Kind                                | Name              | Value                                                       |
| ----------------------------------- | ----------------- | ----------------------------------------------------------- |
| Repository variable                 | `VPS_HOST`        | Server IP or hostname (deploys are skipped while unset)     |
| Repository variable                 | `VPS_USER`        | `deploy`                                                    |
| Repository variable                 | `PHX_HOST`        | `sms.strand.co.ke`                                          |
| Repository variable (optional)      | `VPS_PORT`        | SSH port, default `22`                                      |
| Repository variable (optional)      | `DEPLOY_PATH`     | `/apps/sms-gateway` (default `/opt/sms-gateway`)            |
| Secret, environment `production`    | `VPS_SSH_KEY`     | Private key (`ssh-keygen -t ed25519 -N "" -f deploy_key`)   |
| Secret, environment `production`    | `VPS_KNOWN_HOSTS` | Output of `ssh-keyscan -p <port> <host>`, checked against the server's fingerprint |

Add required reviewers to the `production` environment if you want to
approve each deploy by hand. To deploy `main` without a new push (e.g. right
after filling these in), use **Actions → CI → Run workflow**.

**Rollback:** `ssh deploy@<host> /apps/sms-gateway/deploy/deploy.sh --rollback`
switches back to the previous image. A database backup is taken before every
deploy in `deploy/backups/`, in case a migration needs undoing.

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
