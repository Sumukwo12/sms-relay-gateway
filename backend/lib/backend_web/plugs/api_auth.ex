defmodule BackendWeb.Plugs.ApiAuth do
  @moduledoc """
  Authenticates `/v1` requests with an API key, sent as
  `Authorization: Bearer <key>` or `X-Api-Key: <key>`.

  Assigns `api_client` (the tenant messages are stored under), `api_user`
  (the owning user, or nil for server keys) and `api_key_id`. Suspended
  users' keys are rejected; pending users can read but not send.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Backend.{Accounts, ApiKeys}

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn |> presented_key() |> ApiKeys.authenticate() do
      {:ok, %{user: %{status: "suspended"}}} ->
        deny(conn, :forbidden, "account_suspended", "This account has been suspended.")

      {:ok, %{user: user} = identity} ->
        # Test keys send nothing, so pending accounts can integrate already
        if conn.method == "POST" and user != nil and not identity.test and
             not Accounts.can_send?(user) do
          deny(
            conn,
            :forbidden,
            "account_pending",
            "Your account is waiting for an administrator's approval before it can send SMS."
          )
        else
          conn
          |> assign(:api_client, identity.client)
          |> assign(:api_user, user)
          |> assign(:api_key_id, identity.api_key_id)
          |> assign(:api_test, identity.test)
        end

      :error ->
        deny(
          conn,
          :unauthorized,
          "unauthorized",
          "Provide a valid API key as 'Authorization: Bearer <key>'."
        )
    end
  end

  defp deny(conn, status, error, message) do
    conn
    |> put_status(status)
    |> json(%{success: false, error: error, message: message})
    |> halt()
  end

  defp presented_key(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> key | _] ->
        String.trim(key)

      _ ->
        case get_req_header(conn, "x-api-key") do
          [key | _] -> String.trim(key)
          [] -> nil
        end
    end
  end
end
