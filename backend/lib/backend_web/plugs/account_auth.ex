defmodule BackendWeb.Plugs.SessionAuth do
  @moduledoc """
  Web dashboard sign-in: the session token from the HttpOnly cookie (or
  `Authorization: Bearer ses_…`). Assigns `current_user` or answers 401.
  """

  import Plug.Conn
  alias Backend.Accounts
  alias BackendWeb.AccountJSON

  @cookie "smsg_session"

  def cookie, do: @cookie

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn)

    case conn |> session_token() |> Accounts.get_user_by_session() do
      nil -> AccountJSON.halt_error(conn, :unauthorized, "unauthorized", "Please sign in.")
      user -> assign(conn, :current_user, user)
    end
  end

  def session_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer ses_" <> _ = header | _] -> String.replace_prefix(header, "Bearer ", "")
      _ -> conn.cookies[@cookie]
    end
  end

  @doc "Store a new session in the cookie."
  def put_session_cookie(conn, token) do
    put_resp_cookie(conn, @cookie, token,
      http_only: true,
      same_site: "Lax",
      secure: Application.get_env(:backend, :secure_cookies, false),
      max_age: Accounts.session_ttl_seconds()
    )
  end

  def drop_session_cookie(conn), do: delete_resp_cookie(conn, @cookie)
end

defmodule BackendWeb.Plugs.RequireAdmin do
  @moduledoc "Only admins past this point."
  alias BackendWeb.AccountJSON

  def init(opts), do: opts

  def call(%{assigns: %{current_user: %{role: "admin"}}} = conn, _opts), do: conn

  def call(conn, _opts),
    do: AccountJSON.halt_error(conn, :forbidden, "forbidden", "Administrators only.")
end

defmodule BackendWeb.Plugs.DeviceAuth do
  @moduledoc "SMS Relay app requests: `Authorization: Bearer dev_…`. Assigns `current_device`."

  import Plug.Conn
  alias Backend.Accounts
  alias BackendWeb.AccountJSON

  def init(opts), do: opts

  def call(conn, _opts) do
    token =
      case get_req_header(conn, "authorization") do
        ["Bearer " <> token | _] -> String.trim(token)
        _ -> nil
      end

    case Accounts.authenticate_device(token) do
      {:ok, device} ->
        assign(conn, :current_device, device)

      :error ->
        AccountJSON.halt_error(
          conn,
          :unauthorized,
          "unauthorized",
          "This phone is signed out. Sign in again."
        )
    end
  end
end

defmodule BackendWeb.Plugs.RequireJson do
  @moduledoc """
  Dashboard requests that change something must be JSON. Browsers can't send
  a cross-site JSON request without a CORS preflight, so together with the
  SameSite session cookie this blocks cross-site request forgery.
  """

  import Plug.Conn
  alias BackendWeb.AccountJSON

  def init(opts), do: opts

  def call(%{method: method} = conn, _opts) when method in ["POST", "PATCH", "PUT", "DELETE"] do
    case get_req_header(conn, "content-type") do
      ["application/json" <> _ | _] ->
        conn

      _ ->
        AccountJSON.halt_error(
          conn,
          :unsupported_media_type,
          "unsupported_media_type",
          "Send JSON with Content-Type: application/json."
        )
    end
  end

  def call(conn, _opts), do: conn
end
