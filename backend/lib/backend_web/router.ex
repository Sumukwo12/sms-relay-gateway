defmodule BackendWeb.Router do
  use BackendWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  # ── JSON API routes ─────────────────────────────────────────────────────────
  scope "/api", BackendWeb do
    pipe_through :api

    # SMS verification
    post "/send-code", SmsController, :send_code
    post "/verify-code", SmsController, :verify_code

    # Modem health
    get "/modem/status", SmsController, :modem_status

    # Rate limit info
    get "/rate-limit/:phone", SmsController, :rate_limit_info
  end
end
