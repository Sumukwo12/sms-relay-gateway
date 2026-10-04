# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :backend,
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

  # How long (seconds) a generated code remains valid before expiring
  code_ttl_seconds: 300,

  # Number of digits in the verification code (6 → "483921")
  code_length: 6,

  # Max SMS sends allowed per phone number within a 1-hour rolling window
  rate_limit_per_hour: 3,

  # Wrong guesses allowed before a code is discarded
  max_verify_attempts: 5,

  # SMS body template — %{code} is replaced with the generated code at runtime
  sms_template: "Your verification code is: %{code}. It expires in 5 minutes. Do not share it.",

  # Browser origins allowed to call the JSON API (the Next.js frontend)
  cors_origins: ["http://localhost:3000"]

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

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
