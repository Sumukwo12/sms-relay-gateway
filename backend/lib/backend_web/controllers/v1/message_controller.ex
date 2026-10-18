defmodule BackendWeb.V1.MessageController do
  @moduledoc """
  Notification SMS for integrated systems.

    POST /v1/messages      — queue a message: {to, body, reference?, callback_url?}
    GET  /v1/messages/:id  — current status of a message you queued
  """

  use BackendWeb, :controller

  alias Backend.{Messages, Outbox}
  alias BackendWeb.V1.Errors

  def create(conn, params) do
    client = conn.assigns.api_client

    if Outbox.capacity_available?() do
      case Messages.enqueue(client, params) do
        {:ok, message} ->
          Outbox.kick()

          conn
          |> put_status(:accepted)
          |> json(%{success: true, message: Messages.to_public(message)})

        {:error, field, reason} ->
          Errors.invalid(conn, field, reason)
      end
    else
      Errors.daily_limit(conn)
    end
  end

  def show(conn, %{"id" => id}) do
    case Messages.get_for_client(conn.assigns.api_client, id) do
      nil -> Errors.not_found(conn)
      message -> json(conn, %{success: true, message: Messages.to_public(message)})
    end
  end
end
