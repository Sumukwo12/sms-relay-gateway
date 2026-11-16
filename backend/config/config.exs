# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :backend,
  ecto_repos: [Backend.Repo],
  generators: [timestamp_type: :utc_datetime],

  # ── SMS Gateway Configuration ────────────────────────────────────────────
  # Defaults only — each value can be overridden with an environment
  # variable at boot (see config/runtime.exs).

  # SMS transport: Backend.Modem.Mock (logs messages) or Backend.Modem.UART
  # (real USB GSM modem). Env: MODEM_ADAPTER=mock|uart
  modem_adapter: Backend.Modem.Mock,

  # Serial port the USB GSM modem is connected to.
  # Windows: "COM3", "COM4", etc.  |  Linux: "/dev/ttyUSB0", "/dev/ttyACM0"
  modem_port: "COM3",

  # Baud rate (check your modem's datasheet; 9600 is the most common default)
  modem_baud: 9600,

  # Android SMS Gateway app settings (used when MODEM_ADAPTER=android)
  # Base URL shown in the app's main screen, e.g. "http://192.168.1.5:8080"
  android_sms_url: "http://192.168.1.5:8080",
  android_sms_user: "",
  android_sms_pass: "",

  # SMS Relay phone token (used when MODEM_ADAPTER=phone)
  phone_gateway_token: nil,

  # How long (seconds) a generated code remains valid before expiring
  code_ttl_seconds: 300,

  # Number of digits in the verification code (6 → "483921")
  code_length: 6,

  # Max SMS sends allowed per phone number within a 1-hour rolling window
  rate_limit_per_hour: 3,

  # Max SMS sends allowed per client IP within a 1-hour rolling window
  rate_limit_per_ip_per_hour: 5,

  # Max total SMS sends allowed globally across all clients within a 1-hour rolling window
  rate_limit_global_per_hour: 100,

  # Whether to trust X-Forwarded-For headers from reverse proxies for client IP
  trust_proxy: false,

  # Wrong guesses allowed before a code is discarded
  max_verify_attempts: 5,

  # SMS body template — %{code} is replaced with the generated code at runtime
  sms_template: "Your verification code is: %{code}. It expires in 5 minutes. Do not share it.",

  # Browser origins allowed to call the JSON API (the Next.js frontend)
  cors_origins: ["http://localhost:3000"],

  # ── Integration API (/v1) ────────────────────────────────────────────────
  # One key per internal system, as %{"system_name" => "secret_key"}.
  # Env: API_KEYS="billing:key1,crm:key2"
  api_keys: %{},

  # Whether the unauthenticated /api/send-code + /api/verify-code endpoints
  # (used by the demo frontend) are enabled. Env: PUBLIC_API=true|false
  public_api_enabled: true,

  # Max SMS the outbox sends per rolling 24 hours, to protect the SIM bundle.
  # Env: DAILY_SEND_LIMIT
  daily_send_limit: 500,

  # Delivery attempts per message before it is marked failed
  message_max_attempts: 3,

  # Seconds a queued notification may wait (e.g. phone offline) before it
  # expires undelivered. OTP messages expire with their code instead.
  # Env: MESSAGE_TTL_SECONDS
  message_ttl_seconds: 86_400,

  # How often (ms) the outbox looks for due or retryable messages.
  # nil disables the timer (tests drive the outbox explicitly).
  outbox_poll_ms: 5_000,
  message_max_segments: 4,
  message_retention_days: 30,
  webhook_poll_ms: 5_000,
  webhook_max_attempts: 12,
  monitor_interval_ms: 60_000,
  janitor_interval_ms: 3_600_000,
  alert_webhook_url: nil,
  alert_offline_seconds: 300,
  alert_queue_age_seconds: 600,
  alert_battery_percent: 20,
  # Longer than the relay app's own 30s send timeout, so its answer arrives first
  phone_send_timeout_ms: 40_000

config :backend, Backend.Repo, journal_mode: :wal

# Configure the endpoint
config :backend, BackendWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BackendWeb.ErrorHTML, json: BackendWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Backend.PubSub,
  live_view: [signing_salt: "xCxAcvQM"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# No colocated hooks/JS are used, so skip the node_modules symlink
# (it needs admin rights on Windows and only produces a warning).
config :phoenix_live_view, :colocated_assets, disable_symlink_warning: true

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Filter sensitive parameters from logs (including WebSocket connect params)
config :phoenix, :filter_parameters, ["password", "token"]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
