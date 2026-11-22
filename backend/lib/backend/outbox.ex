defmodule Backend.Outbox do
  @moduledoc """
  Sends queued messages (`Backend.Messages`) through the modem, strictly one
  at a time.

  It wakes up when a message is enqueued (`kick/0`), when the phone
  reconnects, and every `:outbox_poll_ms` to pick up retries and expire
  messages that waited too long. While the phone is offline, messages stay
  queued and are not charged an attempt. Sending also pauses once
  `:daily_send_limit` SMS parts have gone out in the last 24 hours.
  """

  use GenServer
  require Logger

  alias Backend.{Messages, Modem}

  # How long to wait before retrying when the phone is offline or busy
  @offline_retry_seconds 10
  @busy_retry_seconds 5

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Ask the outbox to look for due messages now."
  def kick do
    if Application.get_env(:backend, :outbox_kick_enabled, true) and GenServer.whereis(__MODULE__),
      do: GenServer.cast(__MODULE__, :kick)

    :ok
  end

  @doc "Synchronously send every due message. Returns how many were attempted."
  def drain(timeout \\ 60_000), do: GenServer.call(__MODULE__, :drain, timeout)

  @doc "Whether the rolling 24h send cap has been reached."
  @spec daily_limit_reached?() :: boolean()
  def daily_limit_reached?, do: Messages.sent_last_24h() >= daily_limit()

  @doc """
  Whether a message of `segments` SMS parts can be accepted without
  overrunning the daily cap, counting both the parts sent in the last 24h and
  the parts still queued.
  """
  @spec capacity_available?(pos_integer()) :: boolean()
  def capacity_available?(segments \\ 1),
    do: Messages.sent_last_24h() + Messages.queued_segments() + segments <= daily_limit()

  @doc "The configured rolling 24h send cap, in SMS parts."
  def daily_limit, do: Application.get_env(:backend, :daily_send_limit, 500)

  # ── GenServer ───────────────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    poll_ms = Keyword.get(opts, :poll_ms, Application.get_env(:backend, :outbox_poll_ms))
    state = %{poll_ms: poll_ms, limit_logged?: false}

    if poll_ms, do: {:ok, state, {:continue, :recover}}, else: {:ok, state}
  end

  @impl true
  def handle_continue(:recover, state) do
    Messages.requeue_interrupted()
    send(self(), :poll)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:kick, state) do
    {_count, state} = safely_process_due(state)
    {:noreply, state}
  end

  @impl true
  def handle_call(:drain, _from, state) do
    {count, state} = process_due(state)
    {:reply, count, state}
  end

  @impl true
  def handle_info(:poll, state) do
    {_count, state} = safely_process_due(state, &Messages.expire_stale/0)
    Process.send_after(self(), :poll, state.poll_ms)
    {:noreply, state}
  end

  # ── Sending ─────────────────────────────────────────────────────────────────

  # A database hiccup should cost one round, not the worker: the timer or the
  # next kick tries again.
  defp safely_process_due(state, before \\ fn -> :ok end) do
    before.()
    process_due(state)
  rescue
    exception ->
      Logger.error("[Outbox] Processing failed: #{Exception.message(exception)}")
      {0, state}
  catch
    :exit, reason ->
      Logger.error("[Outbox] Processing failed: #{inspect(reason)}")
      {0, state}
  end

  defp process_due(state, count \\ 0) do
    cond do
      daily_limit_reached?() ->
        unless state.limit_logged? do
          Logger.warning(
            "[Outbox] Daily send limit (#{daily_limit()}) reached; pausing until it frees up"
          )
        end

        {count, %{state | limit_logged?: true}}

      message = Messages.checkout_next() ->
        case deliver(message) do
          :continue -> process_due(%{state | limit_logged?: false}, count + 1)
          :stop -> {count + 1, state}
        end

      true ->
        {count, state}
    end
  end

  # Returns :continue to try the next message, or :stop when the modem is
  # unavailable and the rest of the queue would fail the same way.
  defp deliver(message) do
    case send_sms(message) do
      :ok ->
        Messages.mark_sent(message)
        :continue

      {:error, :modem_disconnected} ->
        Messages.defer(message, :modem_disconnected, @offline_retry_seconds)
        :stop

      {:error, :modem_busy} ->
        Messages.defer(message, :modem_busy, @busy_retry_seconds)
        :stop

      {:error, reason} ->
        Messages.attempt_failed(message, reason)
        :continue
    end
  end

  defp send_sms(message) do
    Modem.send_sms(message.to, message.body, id: message.id)
  catch
    :exit, {:timeout, _} -> {:error, :send_timeout}
    :exit, {:noproc, _} -> {:error, :modem_disconnected}
    :exit, reason -> {:error, {:modem_exit, reason}}
  end
end
