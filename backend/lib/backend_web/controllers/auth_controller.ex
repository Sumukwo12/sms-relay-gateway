defmodule BackendWeb.AuthController do
  @moduledoc """
  Sign-up and sign-in for the web dashboard (session cookie).

    POST /api/auth/register  {email, password, name?}
    POST /api/auth/login     {email, password}
    POST /api/auth/logout
    GET  /api/auth/me        → the signed-in user, or 401
  """

  use BackendWeb, :controller

  alias Backend.{Accounts, RateLimiter}
  alias BackendWeb.{AccountJSON, ClientIp}
  alias BackendWeb.Plugs.SessionAuth

  # Per rolling hour
  @register_per_ip 10
  @login_per_ip 30
  @login_per_email 10

  def register(conn, params) do
    with :ok <- limit(conn, "register:ip:" <> ClientIp.get(conn), @register_per_ip) do
      case Accounts.register(Map.take(params, ["email", "password", "name"])) do
        {:ok, user} ->
          conn
          |> SessionAuth.put_session_cookie(Accounts.create_session(user))
          |> put_status(:created)
          |> json(%{success: true, user: AccountJSON.user(user)})

        {:error, errors} ->
          AccountJSON.errors_response(conn, errors)
      end
    end
  end

  def login(conn, %{"email" => email, "password" => password})
      when is_binary(email) and is_binary(password) do
    with :ok <- limit(conn, "login:ip:" <> ClientIp.get(conn), @login_per_ip),
         :ok <- limit(conn, "login:email:" <> String.downcase(email), @login_per_email) do
      case Accounts.authenticate(email, password) do
        {:ok, user} ->
          conn
          |> SessionAuth.put_session_cookie(Accounts.create_session(user))
          |> json(%{success: true, user: AccountJSON.user(user)})

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

  def logout(conn, _params) do
    conn = fetch_cookies(conn)
    Accounts.delete_session(SessionAuth.session_token(conn))

    conn
    |> SessionAuth.drop_session_cookie()
    |> json(%{success: true})
  end

  def me(conn, _params) do
    conn = fetch_cookies(conn)

    case Accounts.get_user_by_session(SessionAuth.session_token(conn)) do
      nil -> AccountJSON.error(conn, :unauthorized, "unauthorized", "Please sign in.")
      user -> json(conn, %{success: true, user: AccountJSON.user(user)})
    end
  end

  @doc false
  def limit(conn, key, max) do
    case RateLimiter.hit(key, max) do
      :ok ->
        :ok

      {:error, :rate_limited, retry_after} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{
          success: false,
          error: "rate_limited",
          message: "Too many attempts. Try again in #{ceil(retry_after / 60)} minute(s).",
          retry_after_seconds: retry_after
        })
    end
  end
end
