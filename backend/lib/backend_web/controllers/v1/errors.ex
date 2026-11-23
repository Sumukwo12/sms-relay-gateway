defmodule BackendWeb.V1.Errors do
  @moduledoc false
  # Consistent error bodies for the /v1 API: {success: false, error, message, ...}

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def invalid(conn, field, reason),
    do:
      error(conn, :unprocessable_entity, "invalid_request", "#{field} #{reason}", %{field: field})

  def not_found(conn), do: error(conn, :not_found, "not_found", "No such message.")

  def daily_limit(conn) do
    message =
      if conn.assigns[:api_user],
        do: "Your account's daily SMS limit has been reached. Try again later.",
        else: "The gateway's daily SMS limit has been reached. Try again later."

    error(conn, :too_many_requests, "daily_limit_reached", message)
  end

  def error(conn, status, code, message, extra \\ %{}) do
    conn
    |> put_status(status)
    |> json(Map.merge(%{success: false, error: code, message: message}, extra))
  end
end
