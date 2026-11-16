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

  # ── Integration API for internal systems (API key required) ────────────────
  scope "/v1", BackendWeb.V1 do
    pipe_through :integration_api

    post "/messages", MessageController, :create
    get "/messages/:id", MessageController, :show
    post "/otp/send", OtpController, :send_code
    post "/otp/verify", OtpController, :verify
    get "/status", StatusController, :show
  end

  # ── Public JSON API for the demo frontend (disable with PUBLIC_API=false) ───
  scope "/api", BackendWeb do
    pipe_through [:api, :public_api]

    # SMS verification
    post "/send-code", SmsController, :send_code
    post "/verify-code", SmsController, :verify_code

    # Modem health (monitoring belongs on the authenticated GET /v1/status)
    get "/modem/status", SmsController, :modem_status

    # Rate limit info
    get "/rate-limit/:phone", SmsController, :rate_limit_info
  end
end
