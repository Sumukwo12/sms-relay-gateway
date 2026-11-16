defmodule BackendWeb.V1.Idempotency do
  @moduledoc false
  # Clients send `Idempotency-Key: <key>` (or an `idempotency_key` field) so a
  # retried request after a network error returns the message it already
  # queued instead of sending the SMS twice.

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Backend.Messages

  def key(conn, params) do
    case get_req_header(conn, "idempotency-key") do
      [key | _] -> String.trim(key)
      [] -> params["idempotency_key"]
    end
  end

  @doc "Respond with the message an earlier request with the same key queued."
  def replay(conn, message, extra \\ %{}) do
    conn
    |> put_resp_header("idempotent-replayed", "true")
    |> put_status(:ok)
    |> json(Map.merge(%{success: true, message: Messages.to_public(message)}, extra))
  end
end
