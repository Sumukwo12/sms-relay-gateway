defmodule BackendWeb.AppController do
  @moduledoc """
  Sign-in for the SMS Relay Android app. Signing in links the phone to the
  account and returns a device token, which the app then uses for the
  `gateway:phone` WebSocket (`wss://<host>/phone`).

    POST /api/app/login   {email, password, device_name?, model?, app_version?}
                          → {device_token, device, user, socket_url}
    GET  /api/app/me      (Bearer device token) → the account and this phone
    POST /api/app/logout  (Bearer device token) → signs the phone out
  """

  use BackendWeb, :controller

  alias Backend.Accounts
  alias BackendWeb.{AccountJSON, AuthController, ClientIp}

  def login(conn, %{"email" => email, "password" => password} = params)
      when is_binary(email) and is_binary(password) do
    with :ok <- AuthController.limit(conn, "login:ip:" <> ClientIp.get(conn), 30),
         :ok <- AuthController.limit(conn, "login:email:" <> String.downcase(email), 10) do
      case Accounts.authenticate(email, password) do
        {:ok, user} ->
          {:ok, device, token} =
            Accounts.create_device(user, %{
              name: params["device_name"],
              model: params["model"],
              app_version: params["app_version"]
            })

          json(conn, %{
            success: true,
            device_token: token,
            device: AccountJSON.device(device),
            user: AccountJSON.user(user),
            socket_url: socket_url(conn)
          })

        {:error, :suspended} ->
          AccountJSON.error(
            conn,
            :forbidden,
            "account_suspended",
            "This account has been suspended."
          )

        {:error, :invalid_credentials} ->
          AccountJSON.error(
            conn,
            :unauthorized,
            "invalid_credentials",
            "Wrong email or password."
          )
      end
    end
  end

  def login(conn, _params),
    do: AccountJSON.errors_response(conn, %{email: "and password are required"})

  def me(conn, _params) do
    device = conn.assigns.current_device

    json(conn, %{
      success: true,
      user: AccountJSON.user(device.user),
      device: AccountJSON.device(device)
    })
  end

  def logout(conn, _params) do
    {:ok, _} = Accounts.revoke_device(conn.assigns.current_device)
    json(conn, %{success: true})
  end

  # Where the app should connect, as seen by this request (behind the proxy
  # the endpoint's configured URL is the public one)
  defp socket_url(_conn) do
    uri = BackendWeb.Endpoint.struct_url()
    scheme = if uri.scheme == "https", do: "wss", else: "ws"
    port = if uri.port in [80, 443, nil], do: "", else: ":#{uri.port}"
    "#{scheme}://#{uri.host}#{port}/phone"
  end
end
