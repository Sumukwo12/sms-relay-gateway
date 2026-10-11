defmodule Backend.Modem.Phone do
  @moduledoc """
  Modem adapter that sends SMS via a companion Android phone connected
  over a Phoenix Channel WebSocket (`gateway:phone`).

  The phone connects out to the backend, so the backend can run in the cloud
  or on a LAN without needing a public IP or port forwarding.

  ## Behaviour

  Implements `Backend.Modem`:
    - `send_sms/2`: Queues the message and waits for the phone's `sms_result`
      acknowledgment (times out after 30s by default).
    - `status/0`: Returns `:ready` when a phone is actively connected,
      `:disconnected` otherwise. Answers instantly from state.
  """

  use GenServer
  require Logger

  @behaviour Backend.Modem

  defstruct [
    :phone_pid,
    :phone_ref,
    pending: %{},
    device_info: nil,
    send_timeout_ms: 30_000
  ]

  # ── Public API ──────────────────────────────────────────────────────────────

  @impl Backend.Modem
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl Backend.Modem
  def send_sms(phone, message) do
    timeout_ms = get_send_timeout_ms()
    # Call with extra headroom over our internal timeout so handle_info({:timeout, id})
    # or the channel reply answers the caller cleanly.
    call_timeout = timeout_ms + 5_000
    GenServer.call(__MODULE__, {:send_sms, phone, message}, call_timeout)
  end

  @impl Backend.Modem
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc "Register a phone channel process. The newest phone connection wins."
  def register_phone(channel_pid) do
    case GenServer.whereis(__MODULE__) do
      nil -> {:error, :modem_not_running}
      _ -> GenServer.call(__MODULE__, {:register_phone, channel_pid})
    end
  end

  @doc "Unregister a phone channel process if it is currently registered."
  def unregister_phone(channel_pid) do
    case GenServer.whereis(__MODULE__) do
      nil -> :ok
      _ -> GenServer.call(__MODULE__, {:unregister_phone, channel_pid})
    end
  end

  @doc "Handle SMS result reported by the phone."
  def sms_result(id, status, error \\ nil) do
    case GenServer.whereis(__MODULE__) do
      nil -> :ok
      _ -> GenServer.call(__MODULE__, {:sms_result, id, status, error})
    end
  end

  @doc "Update device telemetry info (battery, signal, version)."
  def update_device_info(info) do
    case GenServer.whereis(__MODULE__) do
      nil -> :ok
      _ -> GenServer.cast(__MODULE__, {:update_device_info, info})
    end
  end

  @doc "Current device telemetry info."
  def get_device_info do
    GenServer.call(__MODULE__, :get_device_info)
  end

  # ── GenServer Callbacks ─────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    timeout_ms = Keyword.get(opts, :send_timeout_ms, get_send_timeout_ms())

    {:ok,
     %__MODULE__{
       phone_pid: nil,
       phone_ref: nil,
       pending: %{},
       device_info: nil,
       send_timeout_ms: timeout_ms
     }}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status =
      if state.phone_pid != nil and Process.alive?(state.phone_pid) do
        :ready
      else
        :disconnected
      end

    {:reply, status, state}
  end

  @impl true
  def handle_call(:get_device_info, _from, state) do
    {:reply, state.device_info, state}
  end

  @impl true
  def handle_call({:register_phone, channel_pid}, _from, state) do
    if state.phone_pid != nil and state.phone_pid != channel_pid and
         Process.alive?(state.phone_pid) do
      Logger.info(
        "[Modem.Phone] Replacing existing phone #{inspect(state.phone_pid)} with #{inspect(channel_pid)}"
      )

      if state.phone_ref, do: Process.demonitor(state.phone_ref, [:flush])
      send(state.phone_pid, :disconnect)
    end

    # Any pending sends from the previous phone can no longer succeed
    if map_size(state.pending) > 0 do
      Logger.warning(
        "[Modem.Phone] Aborting #{map_size(state.pending)} pending sends due to phone re-registration"
      )

      for {_id, {caller, timer_ref}} <- state.pending do
        Process.cancel_timer(timer_ref)
        GenServer.reply(caller, {:error, :modem_disconnected})
      end
    end

    ref = Process.monitor(channel_pid)
    new_state = %{state | phone_pid: channel_pid, phone_ref: ref, pending: %{}}
    Logger.info("[Modem.Phone] Phone registered: #{inspect(channel_pid)}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:unregister_phone, channel_pid}, _from, state) do
    if state.phone_pid == channel_pid do
      if state.phone_ref, do: Process.demonitor(state.phone_ref, [:flush])

      for {_id, {caller, timer_ref}} <- state.pending do
        Process.cancel_timer(timer_ref)
        GenServer.reply(caller, {:error, :modem_disconnected})
      end

      Logger.info("[Modem.Phone] Phone unregistered: #{inspect(channel_pid)}")
      {:reply, :ok, %{state | phone_pid: nil, phone_ref: nil, pending: %{}}}
    else
      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:send_sms, phone, message}, from, state) do
    if state.phone_pid == nil or not Process.alive?(state.phone_pid) do
      {:reply, {:error, :modem_disconnected}, state}
    else
      id = generate_id()
      timer_ref = Process.send_after(self(), {:timeout, id}, state.send_timeout_ms)
      payload = %{"id" => id, "to" => phone, "body" => message}

      send(state.phone_pid, {:send_sms, payload})

      pending = Map.put(state.pending, id, {from, timer_ref})
      {:noreply, %{state | pending: pending}}
    end
  end

  @impl true
  def handle_call({:sms_result, id, status, error}, _from, state) do
    case Map.pop(state.pending, id) do
      {nil, _pending} ->
        Logger.debug("[Modem.Phone] Received sms_result for unknown or expired id=#{inspect(id)}")
        {:reply, :ok, state}

      {{caller, timer_ref}, pending} ->
        Process.cancel_timer(timer_ref)

        result =
          case status do
            "sent" ->
              :ok

            "failed" ->
              err = error || "send_failed"
              {:error, err}

            other ->
              {:error, other}
          end

        GenServer.reply(caller, result)
        {:reply, :ok, %{state | pending: pending}}
    end
  end

  @impl true
  def handle_cast({:update_device_info, info}, state) do
    {:noreply, %{state | device_info: info}}
  end

  @impl true
  def handle_info({:timeout, id}, state) do
    case Map.pop(state.pending, id) do
      {nil, _pending} ->
        {:noreply, state}

      {{caller, _timer_ref}, pending} ->
        Logger.warning("[Modem.Phone] Send timed out for id=#{inspect(id)}")
        GenServer.reply(caller, {:error, :send_timeout})
        {:noreply, %{state | pending: pending}}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    if pid == state.phone_pid and ref == state.phone_ref do
      Logger.warning("[Modem.Phone] Phone disconnected: #{inspect(reason)}")

      for {_id, {caller, timer_ref}} <- state.pending do
        Process.cancel_timer(timer_ref)
        GenServer.reply(caller, {:error, :modem_disconnected})
      end

      {:noreply, %{state | phone_pid: nil, phone_ref: nil, pending: %{}}}
    else
      {:noreply, state}
    end
  end

  # ── Private Helpers ─────────────────────────────────────────────────────────

  defp generate_id do
    :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)
  end

  defp get_send_timeout_ms do
    Application.get_env(:backend, :phone_send_timeout_ms, 30_000)
  end
end
