defmodule BackendWeb.GatewayChannel do
  @moduledoc """
  Phoenix Channel topic `gateway:phone` for the SMS Relay mobile app.

  Handles bidirectional communication between the server and the phone:
    - Validates gateway authentication token on join.
    - Server pushes `"send_sms"` `%{id, to, body}` to the phone.
    - Phone pushes `"sms_result"` `%{id, status, error}` to the server.
    - Phone pushes `"sms_delivered"` `%{id}` (marks outbox messages delivered).
      The reply tells the phone it can drop the report from its retry buffer.
    - Phone pushes `"device_info"` `%{battery, signal, app_version}` (telemetry).
  """

  use BackendWeb, :channel
  require Logger

  alias Backend.{Messages, Outbox}
  alias Backend.Modem.Phone, as: PhoneModem

  @impl true
  def join("gateway:phone", _payload, socket) do
    token = socket.assigns[:token]
    expected_token = expected_token()

    if is_binary(expected_token) and byte_size(expected_token) > 0 and
         is_binary(token) and Plug.Crypto.secure_compare(token, expected_token) do
      case PhoneModem.register_phone(self()) do
        :ok ->
          Logger.info("[GatewayChannel] Phone connected: #{inspect(self())}")
          # Send anything that queued up while the phone was offline
          Outbox.kick()
          {:ok, socket}

        {:error, reason} ->
          Logger.error("[GatewayChannel] Failed to register phone: #{inspect(reason)}")
          {:error, %{reason: to_string(reason)}}
      end
    else
      Logger.warning("[GatewayChannel] Rejected connection: invalid gateway token")
      {:error, %{reason: "invalid_token"}}
    end
  end

  @impl true
  def handle_in("sms_result", %{"id" => id} = payload, socket) do
    status = Map.get(payload, "status")
    error = Map.get(payload, "error")
    PhoneModem.sms_result(id, status, error)
    # Also covers results that arrive after the outbox stopped waiting
    if is_binary(id), do: Messages.apply_phone_result(id, status, error)
    {:noreply, socket}
  end

  @impl true
  def handle_in("sms_delivered", %{"id" => id}, socket) when is_binary(id) do
    Logger.info("[GatewayChannel] SMS delivered: #{id}")
    Messages.mark_delivered(id)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("device_info", params, socket) do
    PhoneModem.update_device_info(params)
    {:noreply, socket}
  end

  @impl true
  def handle_in(event, _payload, socket) do
    Logger.warning("[GatewayChannel] Unhandled client event: #{inspect(event)}")
    {:noreply, socket}
  end

  @impl true
  def handle_info({:send_sms, payload}, socket) do
    push(socket, "send_sms", payload)
    {:noreply, socket}
  end

  @impl true
  def handle_info(:disconnect, socket) do
    Logger.info("[GatewayChannel] Terminating older connection in favor of newer phone")
    {:stop, :normal, socket}
  end

  @impl true
  def terminate(reason, _socket) do
    Logger.info("[GatewayChannel] Channel terminated: #{inspect(reason)}")
    PhoneModem.unregister_phone(self())
    :ok
  end

  defp expected_token do
    Application.get_env(:backend, :phone_gateway_token) ||
      System.get_env("PHONE_GATEWAY_TOKEN")
  end
end
