defmodule BackendWeb.V1.MessageController do
  @moduledoc """
  Notification SMS for integrated systems.

    POST /v1/messages      — queue a message: {to, body, reference?, callback_url?}
                             (send an Idempotency-Key header to make retries safe)
    GET  /v1/messages/:id  — current status of a message you queued
  """

  use BackendWeb, :controller

  alias Backend.{Messages, Outbox, Segments}
  alias BackendWeb.V1.{Errors, Idempotency}

  def create(conn, params) do
    client = conn.assigns.api_client
    key = Idempotency.key(conn, params)

    cond do
      existing = is_binary(key) && Messages.get_by_idempotency_key(client, key) ->
        Idempotency.replay(conn, existing)

      not Outbox.capacity_available?(segments(params["body"])) ->
        Errors.daily_limit(conn)

      true ->
        case Messages.enqueue(client, params, idempotency_key: key) do
          {:ok, message} ->
            Outbox.kick()

            conn
            |> put_status(:accepted)
            |> json(%{success: true, message: Messages.to_public(message)})

          {:existing, message} ->
            Idempotency.replay(conn, message)

          {:error, field, reason} ->
            Errors.invalid(conn, field, reason)
        end
    end
  end

  # Invalid bodies are rejected by Messages.enqueue/3; count them as one part
  defp segments(body) when is_binary(body), do: Segments.count(String.trim(body))
  defp segments(_body), do: 1

  def show(conn, %{"id" => id}) do
    case Messages.get_for_client(conn.assigns.api_client, id) do
      nil -> Errors.not_found(conn)
      message -> json(conn, %{success: true, message: Messages.to_public(message)})
    end
  end
end
