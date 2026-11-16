import Config

# Force using SSL in production. This also sets the "strict-security-transport" header,
# known as HSTS. If you have a health check endpoint, you may want to exclude it below.
# Note `:force_ssl` is required to be set at compile-time.
config :backend, BackendWeb.Endpoint,
  force_ssl: [
    rewrite_on: [:x_forwarded_proto],
    exclude: [
      # paths: ["/health"],
      hosts: ["localhost", "127.0.0.1"]
    ]
  ]

# Production sends real SMS through the USB GSM modem
config :backend, modem_adapter: Backend.Modem.UART

# The unauthenticated demo /api endpoints are off in production unless
# PUBLIC_API=true; integrated systems use the authenticated /v1 API.
config :backend, public_api_enabled: false

# Do not print debug messages in production
config :logger, level: :info

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
