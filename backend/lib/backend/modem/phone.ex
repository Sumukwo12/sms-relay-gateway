defmodule Backend.Modem.Phone do
  @moduledoc """
  Modem adapter that sends SMS through phones running the SMS Relay app,
  connected over the `gateway:phone` Phoenix Channel.

  Many phones can be connected at once. Each belongs to an owner:

    - a linked device (`device_id` + `user_id`), signed in with an account;
    - the legacy phone, signed in with the server-wide `PHONE_GATEWAY_TOKEN`.

  A message for a user goes out through that user's phones only (the one
  that connected most recently, or the one the sender picked). Server-level
  messages (`user_id: nil` — the public demo page and `API_KEYS` from the
  environment) go through the legacy phone, or else an admin's phone.

  When the same device (or the legacy token) connects again, the newer
  connection replaces the older one; other phones are unaffected.

  `send_sms/3` waits for the phone's `sms_result` (40s by default, longer
  than the app's own 30s timeout so its answer normally arrives first).
  """

  use GenServer
  require Logger

  @behaviour Backend.Modem

  # ── Public API ──────────────────────────────────────────────────────────────

  @impl Backend.Modem
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl Backend.Modem
  def send_sms(phone, message), do: send_sms(phone, message, [])

  @doc """
  Options: `:id` (outbox message id), `:user_id` (nil = server-level) and
  `:device_id` (send through this phone of the user only).
  """
  @impl Backend.Modem
  def send_sms(phone, message, opts) do
    call_timeout = get_send_timeout_ms() + 5_000
    GenServer.call(__MODULE__, {:send_sms, phone, message, opts}, call_timeout)
  end

  @doc "Whether server-level messages can be sent (legacy or admin phone online)."
  @impl Backend.Modem
  def status, do: GenServer.call(__MODULE__, {:status, nil})

  @doc "Whether this user has a phone online."
  def status(user_id), do: GenServer.call(__MODULE__, {:status, user_id})

  @doc "Who can be sent for right now: `%{users: MapSet, system: boolean}`."
  def available_owners, do: GenServer.call(__MODULE__, :available_owners)

  @doc """
  Register a channel process as a phone. `owner` is
  `%{device_id, user_id, admin?}` for a linked device, or `%{}` for the
  legacy token. A newer connection of the same device replaces the older one.
  """
  def register_phone(channel_pid, owner \\ %{}) do
    case GenServer.whereis(__MODULE__) do
      nil -> {:error, :modem_not_running}
      _ -> GenServer.call(__MODULE__, {:register_phone, channel_pid, owner})
    end
  end

  def unregister_phone(channel_pid) do
    case GenServer.whereis(__MODULE__) do
      nil -> :ok
      _ -> GenServer.call(__MODULE__, {:unregister_phone, channel_pid})
    end
  end

  @doc "A result the phone on `channel_pid` reported for message `id`."
  def sms_result(channel_pid, id, status, error \\ nil) do
    case GenServer.whereis(__MODULE__) do
      nil -> :ok
      _ -> GenServer.call(__MODULE__, {:sms_result, channel_pid, id, status, error})
    end
  end

  @doc "Telemetry (battery, signal, app version) from the phone on `channel_pid`."
  def update_device_info(channel_pid, info) do
    case GenServer.whereis(__MODULE__) do
      nil -> :ok
      _ -> GenServer.cast(__MODULE__, {:update_device_info, channel_pid, info})
    end
  end

  @doc "Telemetry of the phone that sends server-level messages, or nil."
  def get_device_info, do: GenServer.call(__MODULE__, :get_device_info)

  @doc """
  Connected phones as `%{device_id, user_id, connected_at, info}` maps:
  all of them, or one user's.
  """
  def connected(user_id \\ :all) do
    # Empty when another modem adapter is configured
    if GenServer.whereis(__MODULE__),
      do: GenServer.call(__MODULE__, {:connected, user_id}),
      else: []
  end

  @doc "Disconnect a device now (it was signed out)."
  def disconnect_device(device_id), do: cast_if_running({:disconnect, {:device, device_id}})

  @doc "Disconnect every phone of a user (they were suspended)."
  def disconnect_user(user_id), do: cast_if_running({:disconnect, {:user, user_id}})

  defp cast_if_running(msg) do
    if GenServer.whereis(__MODULE__), do: GenServer.cast(__MODULE__, msg)
    :ok
  end

  # ── GenServer Callbacks ─────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    # phones: %{pid => %{key, device_id, user_id, admin?, ref, connected_at, info}}
    # pending: %{message_id => {caller, timer_ref, pid}}
    {:ok,
     %{
       phones: %{},
       pending: %{},
       send_timeout_ms: Keyword.get(opts, :send_timeout_ms, get_send_timeout_ms())
     }}
  end

  @impl true
  def handle_call({:status, user_id}, _from, state) do
    status = if candidates(state, user_id, nil) == [], do: :disconnected, else: :ready
    {:reply, status, state}
  end

  def handle_call(:available_owners, _from, state) do
    users = for {_pid, %{user_id: id}} <- state.phones, is_integer(id), into: MapSet.new(), do: id
    {:reply, %{users: users, system: candidates(state, nil, nil) != []}, state}
  end

  def handle_call(:get_device_info, _from, state) do
    info =
      case candidates(state, nil, nil) do
        [{_pid, phone} | _] -> phone.info
        [] -> nil
      end

    {:reply, info, state}
  end

  def handle_call({:connected, user_id}, _from, state) do
    list =
      for {_pid, phone} <- state.phones, user_id == :all or phone.user_id == user_id do
        Map.take(phone, [:device_id, :user_id, :connected_at, :info])
      end

    {:reply, list, state}
  end

  def handle_call({:register_phone, pid, owner}, _from, state) do
    device_id = owner[:device_id]
    key = if device_id, do: {:device, device_id}, else: :legacy

    # A newer connection of the same phone replaces the older one
    state =
      Enum.reduce(state.phones, state, fn {old_pid, phone}, acc ->
        if phone.key == key and old_pid != pid do
          Logger.info("[Modem.Phone] Replacing #{inspect(old_pid)} with #{inspect(pid)}")
          send(old_pid, :disconnect)
          drop_phone(acc, old_pid, phone)
        else
          acc
        end
      end)

    state = if old = state.phones[pid], do: drop_phone(state, pid, old), else: state

    phone = %{
      key: key,
      device_id: device_id,
      user_id: owner[:user_id],
      admin?: owner[:admin?] == true,
      ref: Process.monitor(pid),
      connected_at: System.monotonic_time(),
      info: nil
    }

    Logger.info("[Modem.Phone] Phone registered: #{inspect(pid)} #{inspect(key)}")
    {:reply, :ok, put_in(state.phones[pid], phone)}
  end

  def handle_call({:unregister_phone, pid}, _from, state) do
    case state.phones[pid] do
      nil ->
        {:reply, :ok, state}

      phone ->
        Logger.info("[Modem.Phone] Phone unregistered: #{inspect(pid)}")
        {:reply, :ok, drop_phone(state, pid, phone)}
    end
  end

  def handle_call({:send_sms, phone_number, message, opts}, from, state) do
    case candidates(state, opts[:user_id], opts[:device_id]) do
      [] ->
        {:reply, {:error, :modem_disconnected}, state}

      [{pid, _phone} | _] ->
        id = opts[:id] || generate_id()
        timer_ref = Process.send_after(self(), {:timeout, id}, state.send_timeout_ms)
        send(pid, {:send_sms, %{"id" => id, "to" => phone_number, "body" => message}})
        {:noreply, put_in(state.pending[id], {from, timer_ref, pid})}
    end
  end

  def handle_call({:sms_result, pid, id, status, error}, _from, state) do
    case state.pending[id] do
      # Only the phone the message went to can answer for it
      {caller, timer_ref, ^pid} ->
        Process.cancel_timer(timer_ref)
        GenServer.reply(caller, result(status, error))
        {:reply, :ok, %{state | pending: Map.delete(state.pending, id)}}

      _ ->
        Logger.debug("[Modem.Phone] sms_result for unknown or expired id=#{inspect(id)}")
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_cast({:update_device_info, pid, info}, state) do
    case state.phones[pid] do
      nil -> {:noreply, state}
      _phone -> {:noreply, put_in(state.phones[pid].info, info)}
    end
  end

  def handle_cast({:disconnect, target}, state) do
    for {pid, phone} <- state.phones, matches?(phone, target), do: send(pid, :disconnect)
    {:noreply, state}
  end

  @impl true
  def handle_info({:timeout, id}, state) do
    case Map.pop(state.pending, id) do
      {nil, _} ->
        {:noreply, state}

      {{caller, _timer_ref, _pid}, pending} ->
        Logger.warning("[Modem.Phone] Send timed out for id=#{inspect(id)}")
        GenServer.reply(caller, {:error, :send_timeout})
        {:noreply, %{state | pending: pending}}
    end
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    case state.phones[pid] do
      %{ref: ^ref} = phone ->
        Logger.warning("[Modem.Phone] Phone disconnected: #{inspect(reason)}")
        {:noreply, drop_phone(state, pid, phone)}

      _ ->
        {:noreply, state}
    end
  end

  # ── Private Helpers ─────────────────────────────────────────────────────────

  # Phones that may send for `user_id` (nil = server-level), best first:
  # the legacy phone, then the most recently connected.
  defp candidates(state, user_id, device_id) do
    state.phones
    |> Enum.filter(fn {pid, phone} ->
      Process.alive?(pid) and routes?(phone, user_id) and
        (is_nil(device_id) or phone.device_id == device_id)
    end)
    |> Enum.sort_by(fn {_pid, phone} -> {phone.key != :legacy, -phone.connected_at} end)
  end

  defp routes?(phone, nil), do: phone.key == :legacy or phone.admin?
  defp routes?(phone, user_id), do: phone.user_id == user_id

  defp matches?(phone, {:device, id}), do: phone.device_id == id
  defp matches?(phone, {:user, id}), do: phone.user_id == id

  # Forget a phone and fail the sends still waiting on it
  defp drop_phone(state, pid, phone) do
    Process.demonitor(phone.ref, [:flush])

    {failed, pending} =
      Enum.split_with(state.pending, fn {_id, {_caller, _timer, p}} -> p == pid end)

    for {_id, {caller, timer_ref, _pid}} <- failed do
      Process.cancel_timer(timer_ref)
      GenServer.reply(caller, {:error, :modem_disconnected})
    end

    %{state | phones: Map.delete(state.phones, pid), pending: Map.new(pending)}
  end

  defp result("sent", _error), do: :ok
  defp result("failed", error), do: {:error, error || "send_failed"}
  defp result(other, _error), do: {:error, other}

  defp generate_id, do: :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)

  defp get_send_timeout_ms, do: Application.get_env(:backend, :phone_send_timeout_ms, 40_000)
end
