defmodule BackendWeb.Router do
  use BackendWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :public_api do
    plug BackendWeb.Plugs.PublicApi
  end

  pipeline :integration_api do
    plug :accepts, ["json"]
    plug BackendWeb.Plugs.ApiAuth
  end

  # Dashboard and app APIs: JSON only (see RequireJson for why)
  pipeline :account_api do
    plug :accepts, ["json"]
    plug BackendWeb.Plugs.RequireJson
  end

  pipeline :signed_in do
    plug BackendWeb.Plugs.SessionAuth
  end

  pipeline :admin do
    plug BackendWeb.Plugs.RequireAdmin
  end

  pipeline :device do
    plug BackendWeb.Plugs.DeviceAuth
  end

  # ── Integration API (API key required) ─────────────────────────────────────
  scope "/v1", BackendWeb.V1 do
    pipe_through :integration_api

    post "/messages", MessageController, :create
    get "/messages/:id", MessageController, :show
    post "/otp/send", OtpController, :send_code
    post "/otp/verify", OtpController, :verify
    get "/status", StatusController, :show
  end

  # ── Accounts (web dashboard, session cookie) ───────────────────────────────
  scope "/api/auth", BackendWeb do
    pipe_through :account_api

    post "/register", AuthController, :register
    post "/login", AuthController, :login
    post "/logout", AuthController, :logout
    get "/me", AuthController, :me
  end

  scope "/api/account", BackendWeb do
    pipe_through [:account_api, :signed_in]

    get "/", AccountController, :show
    post "/password", AccountController, :change_password
    post "/webhook-secret", AccountController, :rotate_webhook_secret
    get "/devices", AccountController, :devices
    patch "/devices/:id", AccountController, :update_device
    delete "/devices/:id", AccountController, :delete_device
    get "/api-keys", AccountController, :api_keys
    post "/api-keys", AccountController, :create_api_key
    delete "/api-keys/:id", AccountController, :delete_api_key
    get "/messages", AccountController, :messages
    post "/console/sms", AccountController, :console_sms
    post "/console/otp/send", AccountController, :console_otp_send
    post "/console/otp/verify", AccountController, :console_otp_verify
  end

  scope "/api/admin", BackendWeb do
    pipe_through [:account_api, :signed_in, :admin]

    get "/overview", AdminController, :overview
    get "/users", AdminController, :users
    patch "/users/:id", AdminController, :update_user
    get "/devices", AdminController, :devices
  end

  # ── SMS Relay app sign-in (device token) ───────────────────────────────────
  scope "/api/app", BackendWeb do
    pipe_through :account_api

    post "/login", AppController, :login

    scope "/" do
      pipe_through :device

      get "/me", AppController, :me
      post "/logout", AppController, :logout
    end
  end

  # ── Public JSON API for the demo page (disable with PUBLIC_API=false) ──────
  scope "/api", BackendWeb do
    pipe_through [:api, :public_api]

    # SMS verification
    post "/send-code", SmsController, :send_code
    post "/verify-code", SmsController, :verify_code

    # Gateway health (monitoring belongs on the authenticated GET /v1/status)
    get "/modem/status", SmsController, :modem_status

    # Rate limit info
    get "/rate-limit/:phone", SmsController, :rate_limit_info
  end
end
