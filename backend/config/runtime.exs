import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/backend start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :backend, BackendWeb.Endpoint, server: true
end

config :backend, BackendWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# ── SMS Gateway overrides from the environment ────────────────────────────
# Skipped in test so the suite always runs against the defaults + mock modem.
if config_env() != :test do
  env_int = fn name ->
    case System.get_env(name) do
      nil -> nil
      value -> String.to_integer(value)
    end
  end

  case System.get_env("MODEM_ADAPTER") do
    nil -> :ok
    "uart" -> config :backend, modem_adapter: Backend.Modem.UART
    "mock" -> config :backend, modem_adapter: Backend.Modem.Mock
    "android" -> config :backend, modem_adapter: Backend.Modem.Android
    other -> raise "MODEM_ADAPTER must be \"uart\", \"mock\", or \"android\", got: #{inspect(other)}"
  end

  [
    modem_port: System.get_env("MODEM_PORT"),
    modem_baud: env_int.("MODEM_BAUD"),
    android_sms_url: System.get_env("ANDROID_SMS_URL"),
    android_sms_user: System.get_env("ANDROID_SMS_USER"),
    android_sms_pass: System.get_env("ANDROID_SMS_PASS"),
    code_ttl_seconds: env_int.("CODE_TTL_SECONDS"),
    code_length: env_int.("CODE_LENGTH"),
    rate_limit_per_hour: env_int.("RATE_LIMIT_PER_HOUR"),
    max_verify_attempts: env_int.("MAX_VERIFY_ATTEMPTS"),
    sms_template: System.get_env("SMS_TEMPLATE")
  ]
  |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  |> then(&config(:backend, &1))

  # Comma-separated list, e.g. "https://app.example.com,http://localhost:3000"
  if origins = System.get_env("FRONTEND_ORIGIN") do
    config :backend,
      cors_origins: origins |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
  end
end

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :backend, BackendWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/backend_web/router\.ex$"E,
        ~r"lib/backend_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :backend, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :backend, BackendWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :backend, BackendWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :backend, BackendWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
