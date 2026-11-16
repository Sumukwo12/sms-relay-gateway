defmodule Backend.Monitor do
  @moduledoc """
  Watches the gateway and raises alerts, so a dead phone is noticed before
  OTPs start expiring in the queue.

  Every `:monitor_interval_ms` it checks:

    * `modem_offline` — the phone/modem has not been ready for
      `:alert_offline_seconds` (default 5 min)
    * `queue_stuck` — a message has waited more than
      `:alert_queue_age_seconds` (default 10 min)
    * `battery_low` — the relay phone is below `:alert_battery_percent`
      (default 20%) and not charging
    * `daily_limit_near` — 90% of the daily SMS part cap is used

  An alert is announced once when it starts and once when it clears: always
  in the log, and as a JSON POST to `:alert_webhook_url` when set. The body
  has `text` (Slack) and `content` (Discord) fields plus `alert` and
  `status` (`"firing"` | `"resolved"`) for anything else. Current alerts are
  also listed in `GET /v1/status`.
  """

  use GenServer
  require Logger

  alias Backend.{Messages, Modem, Outbox}

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Alerts currently firing, as `%{alert => message}`."
  @spec active_alerts() :: %{optional(String.t()) => String.t()}
  def active_alerts do
    if GenServer.whereis(__MODULE__), do: GenServer.call(__MODULE__, :active_alerts), else: %{}
  end

  @doc "Run the checks now (used by tests). Returns the alerts firing afterwards."
  def check_now, do: GenServer.call(__MODULE__, :check_now)

  # ── GenServer ───────────────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    interval =
      Keyword.get(opts, :interval_ms, Application.get_env(:backend, :monitor_interval_ms))

    if interval, do: Process.send_after(self(), :check, interval)
    {:ok, %{interval: interval, offline_since: nil, active: %{}}}
  end

  @impl true
  def handle_call(:active_alerts, _from, state), do: {:reply, state.active, state}

  def handle_call(:check_now, _from, state) do
    state = check(state)
    {:reply, state.active, state}
  end

  @impl true
  def handle_info(:check, state) do
    state = check(state)
    Process.send_after(self(), :check, state.interval)
    {:noreply, state}
  end

  # ── Checks ──────────────────────────────────────────────────────────────────

  defp check(state) do
    now = DateTime.utc_now()

    offline_since =
      case modem_status() do
        :ready -> nil
        _ -> state.offline_since || now
      end

    firing =
      [
        offline_alert(offline_since, now),
        queue_alert(now),
        battery_alert(),
        daily_limit_alert()
      ]
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    for {alert, message} <- firing,
        not Map.has_key?(state.active, alert),
        do: announce(alert, "firing", message)

    for {alert, _message} <- state.active,
        not Map.has_key?(firing, alert),
        do: announce(alert, "resolved", "Resolved: #{alert}")

    %{state | offline_since: offline_since, active: firing}
  rescue
    exception ->
      Logger.error("[Monitor] Check failed: #{Exception.message(exception)}")
      state
  end

  defp offline_alert(nil, _now), do: nil

  defp offline_alert(since, now) do
    seconds = DateTime.diff(now, since)

    if seconds >= setting(:alert_offline_seconds, 300) do
      {"modem_offline",
       "SMS gateway phone/modem has been offline for #{div(seconds, 60)} min; " <>
         "#{Messages.queue_depth()} message(s) waiting."}
    end
  end

  defp queue_alert(now) do
    with %DateTime{} = oldest <- Messages.oldest_queued_at(),
         age when age >= 0 <- DateTime.diff(now, oldest),
         true <- age >= setting(:alert_queue_age_seconds, 600) do
      {"queue_stuck",
       "Oldest queued SMS has waited #{div(age, 60)} min; " <>
         "#{Messages.queue_depth()} message(s) waiting."}
    else
      _ -> nil
    end
  end

  defp battery_alert do
    with Backend.Modem.Phone <- Modem.adapter(),
         %{"battery" => battery} = info when is_number(battery) <-
           Backend.Modem.Phone.get_device_info(),
         false <- info["is_charging"] == true,
         true <- battery < setting(:alert_battery_percent, 20) do
      {"battery_low", "SMS relay phone battery is at #{battery}% and not charging."}
    else
      _ -> nil
    end
  catch
    :exit, _ -> nil
  end

  defp daily_limit_alert do
    limit = Outbox.daily_limit()
    sent = Messages.sent_last_24h()

    if limit > 0 and sent >= limit * 0.9 do
      {"daily_limit_near", "#{sent} of #{limit} daily SMS parts used in the last 24h."}
    end
  end

  defp modem_status do
    Modem.status()
  catch
    :exit, _ -> :disconnected
  end

  # ── Notification ────────────────────────────────────────────────────────────

  defp announce(alert, status, message) do
    if status == "firing",
      do: Logger.warning("[Monitor] ALERT #{alert}: #{message}"),
      else: Logger.info("[Monitor] #{message}")

    if url = Application.get_env(:backend, :alert_webhook_url) do
      text =
        if status == "firing", do: "⚠️ SMS gateway: #{message}", else: "✅ SMS gateway: #{message}"

      body = %{text: text, content: text, alert: alert, status: status, message: message}

      Task.Supervisor.start_child(Backend.TaskSupervisor, fn ->
        options =
          [json: body, retry: :transient, max_retries: 3, receive_timeout: 10_000]
          |> Keyword.merge(Application.get_env(:backend, :alert_req_options, []))

        case Req.post(url, options) do
          {:ok, %Req.Response{status: code}} when code in 200..299 -> :ok
          other -> Logger.error("[Monitor] Could not deliver alert #{alert}: #{inspect(other)}")
        end
      end)
    end
  end

  defp setting(key, default), do: Application.get_env(:backend, key, default)
end
