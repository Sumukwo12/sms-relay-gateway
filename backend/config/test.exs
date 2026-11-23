import Config

config :backend, Backend.Repo,
  database: Path.expand("../backend_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# Tests drive the outbox explicitly and run migrations through the mix alias
config :backend,
  outbox_poll_ms: nil,
  outbox_kick_enabled: false,
  webhook_poll_ms: nil,
  webhook_kick_enabled: false,
  monitor_interval_ms: nil,
  janitor_interval_ms: nil,
  run_migrations_on_boot: false,
  # Fast password hashing in tests
  password_iterations: 1_000,
  api_keys: %{"test_system" => "test-api-key", "other_system" => "other-api-key"},
  # Webhooks go to a Req.Test stub instead of the network
  webhook_req_options: [plug: {Req.Test, Backend.Webhooks}, retry: false]

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :backend, BackendWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "m+qbLfN0VxtGSq4iva2EDIwu1O4LkSsXJjVQfmdanULt7utrL/RnBklswH4PlYxt",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
