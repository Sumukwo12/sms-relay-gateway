defmodule BackendWeb.Plugs.ApiAuth do
  @moduledoc """
  Authenticates `/v1` requests with a per-system API key, sent as
  `Authorization: Bearer <key>` or `X-Api-Key: <key>`. Assigns the system
  name to `conn.assigns.api_client`.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Backend.ApiKeys

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn |> presented_key() |> ApiKeys.authenticate() do
      {:ok, client} ->
        assign(conn, :api_client, client)

      :error ->
        conn
        |> put_status(:unauthorized)
        |> json(%{
          success: false,
          error: "unauthorized",
          message: "Provide a valid API key as 'Authorization: Bearer <key>'."
        })
        |> halt()
    end
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
