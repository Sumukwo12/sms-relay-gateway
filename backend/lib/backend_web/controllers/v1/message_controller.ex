defmodule BackendWeb.V1.MessageController do
  @moduledoc """
  Notification SMS for integrated systems.

    POST /v1/messages      — queue a message: {to, body, reference?, callback_url?, device_id?}
                             (send an Idempotency-Key header to make retries safe)
    GET  /v1/messages/:id  — current status of a message you queued
  """

  use BackendWeb, :controller

  alias Backend.{Messages, SmsGateway}
  alias BackendWeb.V1.{Errors, Idempotency, Owner}

  def create(conn, params) do
    with {:ok, owner_opts} <- Owner.opts(conn, params) do
      opts = [idempotency_key: Idempotency.key(conn, params)] ++ owner_opts

      case SmsGateway.queue_message(conn.assigns.api_client, params, opts) do
        {:ok, message} ->
          conn
          |> put_status(:accepted)
          |> json(%{success: true, message: Messages.to_public(message)})

        {:existing, message} ->
          Idempotency.replay(conn, message)

        {:error, :daily_limit_reached} ->
          Errors.daily_limit(conn)

        {:error, {:invalid, field, reason}} ->
          Errors.invalid(conn, field, reason)
      end
    end
  end

  def show(conn, %{"id" => id}) do
    case Messages.get_for_client(conn.assigns.api_client, id) do
      nil -> Errors.not_found(conn)
      message -> json(conn, %{success: true, message: Messages.to_public(message)})
    end
  end
end
