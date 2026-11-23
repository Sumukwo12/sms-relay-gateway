defmodule BackendWeb.GatewayChannel do
  @moduledoc """
  Phoenix Channel topic `gateway:phone` for the SMS Relay mobile app.

  The socket's `token` is either a device token (the app signed in to an
  account, `POST /api/app/login`) or the server-wide `PHONE_GATEWAY_TOKEN`
  (the legacy single-phone setup).

    - Server pushes `"send_sms"` `%{id, to, body}` to the phone.
    - Phone pushes `"sms_result"` `%{id, status, error}` to the server.
    - Phone pushes `"sms_delivered"` `%{id}` (marks outbox messages delivered).
      The reply tells the phone it can drop the report from its retry buffer.
    - Phone pushes `"device_info"` `%{battery, signal, app_version}` (telemetry).

  A phone can only report on messages its owner sent.
  """

  use BackendWeb, :channel
  require Logger

  alias Backend.{Accounts, Messages, Outbox}
  alias Backend.Modem.Phone, as: PhoneModem

  @impl true
  def join("gateway:phone", payload, socket) do
    case authenticate(socket.assigns[:token]) do
      :error ->
        Logger.warning("[GatewayChannel] Rejected connection: invalid gateway token")
        {:error, %{reason: "invalid_token"}}

      # The app's "Test Connection" only checks the URL and token. Registering it
      # would evict the live relay connection (newest phone wins) and then leave
      # no phone at all once the probe disconnects.
      {:ok, _owner} when is_map(payload) and :erlang.map_get("probe", payload) == true ->
        {:ok, assign(socket, :probe, true)}

      {:ok, owner} ->
        register(assign(socket, :owner, owner))
    end
  end

  defp register(socket) do
    owner = socket.assigns.owner

    case PhoneModem.register_phone(self(), owner) do
      :ok ->
        if owner.device_id do
          Accounts.touch_device(owner.device_id)
          device_event(owner, "device.connected")
        end

        Logger.info("[GatewayChannel] Phone connected: #{inspect(self())} #{describe(owner)}")
        # Send anything that queued up while the phone was offline
        Outbox.kick()
        {:ok, socket}

      {:error, reason} ->
        Logger.error("[GatewayChannel] Failed to register phone: #{inspect(reason)}")
        {:error, %{reason: to_string(reason)}}
    end
  end

  @impl true
  def handle_in(_event, _payload, %{assigns: %{probe: true}} = socket), do: {:noreply, socket}

  def handle_in("sms_result", %{"id" => id} = payload, socket) do
    status = Map.get(payload, "status")
    error = Map.get(payload, "error")
    PhoneModem.sms_result(self(), id, status, error)
    # Also covers results that arrive after the outbox stopped waiting
    if owns?(socket, id), do: Messages.apply_phone_result(id, status, error)
    {:noreply, socket}
  end

  def handle_in("sms_delivered", %{"id" => id}, socket) when is_binary(id) do
    if owns?(socket, id) do
      Logger.info("[GatewayChannel] SMS delivered: #{id}")
      Messages.mark_delivered(id)
    end

    # Acknowledge either way, so the app stops retrying the report
    {:reply, :ok, socket}
  end

  def handle_in("device_info", params, socket) do
    PhoneModem.update_device_info(self(), params)

    with %{device_id: id} when is_integer(id) <- socket.assigns.owner do
      version = if is_binary(params["app_version"]), do: params["app_version"]
      Accounts.touch_device(id, version)
    end

    {:noreply, socket}
  end

  def handle_in(event, _payload, socket) do
    Logger.warning("[GatewayChannel] Unhandled client event: #{inspect(event)}")
    {:noreply, socket}
  end

  @impl true
  def handle_info({:send_sms, payload}, socket) do
    push(socket, "send_sms", payload)
    {:noreply, socket}
  end

  def handle_info(:disconnect, socket) do
    Logger.info("[GatewayChannel] Closing connection (replaced, signed out or suspended)")
    {:stop, :normal, socket}
  end

  @impl true
  def terminate(_reason, %{assigns: %{probe: true}}), do: :ok

  def terminate(reason, socket) do
    Logger.info("[GatewayChannel] Channel terminated: #{inspect(reason)}")
    PhoneModem.unregister_phone(self())

    # Not when the same phone already reconnected (it replaced this connection)
    with %{device_id: id, user_id: user_id} = owner when is_integer(id) <- socket.assigns[:owner],
         false <- Enum.any?(PhoneModem.connected(user_id), &(&1.device_id == id)) do
      device_event(owner, "device.disconnected")
    end

    :ok
  end

  defp device_event(%{device_id: id, user_id: user_id}, event) do
    case Backend.Repo.get(Backend.Accounts.Device, id) do
      nil -> :ok
      device -> Backend.Webhooks.device_event(user_id, device, event)
    end
  rescue
    # Never let a webhook problem break the phone connection
    exception ->
      Logger.error("[GatewayChannel] #{event} webhook failed: #{Exception.message(exception)}")
  end

  # ── Authentication ──────────────────────────────────────────────────────────

  defp authenticate(token) when is_binary(token) do
    case Accounts.authenticate_device(token) do
      {:ok, device} ->
        {:ok,
         %{device_id: device.id, user_id: device.user_id, admin?: device.user.role == "admin"}}

      :error ->
        if valid_legacy_token?(token),
          do: {:ok, %{device_id: nil, user_id: nil, admin?: false}},
          else: :error
    end
  end

  defp authenticate(_), do: :error

  defp valid_legacy_token?(token) do
    expected = expected_token()

    is_binary(expected) and byte_size(expected) > 0 and
      Plug.Crypto.secure_compare(token, expected)
  end

  # The legacy phone and admins' phones carry server-level messages; a
  # user's phone carries only that user's.
  defp owns?(socket, id) when is_binary(id) do
    case Messages.get(id) do
      nil -> false
      %{user_id: nil} -> socket.assigns.owner.user_id == nil or socket.assigns.owner.admin?
      %{user_id: user_id} -> socket.assigns.owner.user_id == user_id
    end
  end

  defp owns?(_socket, _id), do: false

  defp describe(%{device_id: nil}), do: "(legacy token)"
  defp describe(%{device_id: id, user_id: user_id}), do: "(device #{id}, user #{user_id})"

  defp expected_token do
    Application.get_env(:backend, :phone_gateway_token) ||
      System.get_env("PHONE_GATEWAY_TOKEN")
  end
end
