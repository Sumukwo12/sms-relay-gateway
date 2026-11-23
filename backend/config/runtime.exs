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
    nil ->
      :ok

    "uart" ->
      config :backend, modem_adapter: Backend.Modem.UART

    "mock" ->
      config :backend, modem_adapter: Backend.Modem.Mock

    "android" ->
      config :backend, modem_adapter: Backend.Modem.Android

    "phone" ->
      config :backend, modem_adapter: Backend.Modem.Phone

    other ->
      raise "MODEM_ADAPTER must be \"uart\", \"mock\", \"android\", or \"phone\", got: #{inspect(other)}"
  end

  [
    modem_port: System.get_env("MODEM_PORT"),
    modem_baud: env_int.("MODEM_BAUD"),
    android_sms_url: System.get_env("ANDROID_SMS_URL"),
    android_sms_user: System.get_env("ANDROID_SMS_USER"),
    android_sms_pass: System.get_env("ANDROID_SMS_PASS"),
    phone_gateway_token: System.get_env("PHONE_GATEWAY_TOKEN"),
    code_ttl_seconds: env_int.("CODE_TTL_SECONDS"),
    code_length: env_int.("CODE_LENGTH"),
    rate_limit_per_hour: env_int.("RATE_LIMIT_PER_HOUR"),
    rate_limit_per_ip_per_hour: env_int.("RATE_LIMIT_PER_IP_PER_HOUR"),
    rate_limit_global_per_hour: env_int.("RATE_LIMIT_GLOBAL_PER_HOUR"),
    trust_proxy:
      if(System.get_env("TRUST_PROXY"), do: System.get_env("TRUST_PROXY") == "true", else: nil),
    max_verify_attempts: env_int.("MAX_VERIFY_ATTEMPTS"),
    sms_template: System.get_env("SMS_TEMPLATE"),
    daily_send_limit: env_int.("DAILY_SEND_LIMIT"),
    message_max_attempts: env_int.("MESSAGE_MAX_ATTEMPTS"),
    message_ttl_seconds: env_int.("MESSAGE_TTL_SECONDS"),
    message_max_segments: env_int.("MESSAGE_MAX_SEGMENTS"),
    message_retention_days: env_int.("MESSAGE_RETENTION_DAYS"),
    webhook_max_attempts: env_int.("WEBHOOK_MAX_ATTEMPTS"),
    alert_webhook_url: System.get_env("ALERT_WEBHOOK_URL"),
    alert_offline_seconds: env_int.("ALERT_OFFLINE_SECONDS"),
    alert_queue_age_seconds: env_int.("ALERT_QUEUE_AGE_SECONDS"),
    alert_battery_percent: env_int.("ALERT_BATTERY_PERCENT"),
    user_daily_send_limit: env_int.("USER_DAILY_SEND_LIMIT"),
    default_country_code: System.get_env("DEFAULT_COUNTRY_CODE"),
    admin:
      with(
        email when is_binary(email) and email != "" <- System.get_env("ADMIN_EMAIL"),
        password when is_binary(password) and byte_size(password) >= 8 <-
          System.get_env("ADMIN_PASSWORD"),
        do: {email, password},
        else: (_ -> nil)
      ),
    public_api_enabled:
      if(System.get_env("PUBLIC_API"), do: System.get_env("PUBLIC_API") == "true", else: nil)
  ]
  |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  |> then(&config(:backend, &1))

  # One key per internal system: "billing:key1,crm:key2"
  if keys = System.get_env("API_KEYS") do
    api_keys =
      keys
      |> String.split(",", trim: true)
      |> Map.new(fn pair ->
        case pair |> String.trim() |> String.split(":", parts: 2) do
          [name, key] when name != "" and byte_size(key) >= 16 ->
            {String.trim(name), String.trim(key)}

          _ ->
            raise "API_KEYS entries must look like name:key with keys of at least 16 characters"
        end
      end)

    config :backend, api_keys: api_keys
  end

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

  # Served over HTTPS by the reverse proxy
  config :backend, secure_cookies: true

  # Nothing sends SMS without signing in: the unauthenticated demo API is off
  # unless PUBLIC_API=true is set explicitly
  unless System.get_env("PUBLIC_API"), do: config(:backend, public_api_enabled: false)

  config :backend, Backend.Repo,
    database:
      System.get_env("DATABASE_PATH") ||
        raise(
          "environment variable DATABASE_PATH is missing, e.g. /var/lib/sms-gateway/gateway.db"
        ),
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

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
