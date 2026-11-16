defmodule Backend.Janitor do
  @moduledoc """
  Periodic clean-up so the database doesn't grow forever or keep personal
  data longer than needed. Every `:janitor_interval_ms` (default hourly) it
  deletes:

    * expired verification codes
    * finished messages (sent, delivered, failed) older than
      `:message_retention_days` (default 30; at least 2, since the daily
      cap looks back 24 hours)
    * finished webhook deliveries older than the same retention

  Message bodies are already erased as soon as a message is finished.
  """

  use GenServer
  require Logger

  alias Backend.{CodeStore, Messages, Webhooks}

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Run the clean-up now. Returns what was deleted."
  @spec run() :: %{
          codes: non_neg_integer(),
          messages: non_neg_integer(),
          webhooks: non_neg_integer()
        }
  def run do
    cutoff = DateTime.add(DateTime.utc_now(), -retention_days() * 86_400, :second)

    result = %{
      codes: CodeStore.purge_expired(),
      messages: Messages.purge_finished_before(cutoff),
      webhooks: Webhooks.purge_finished_before(cutoff)
    }

    if result.messages > 0 or result.webhooks > 0 do
      Logger.info(
        "[Janitor] Deleted #{result.messages} message(s) and #{result.webhooks} webhook(s) older than #{retention_days()} days"
      )
    end

    result
  end

  @impl true
  def init(opts) do
    interval =
      Keyword.get(opts, :interval_ms, Application.get_env(:backend, :janitor_interval_ms))

    if interval, do: send(self(), :run)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:run, state) do
    try do
      run()
    rescue
      exception -> Logger.error("[Janitor] Clean-up failed: #{Exception.message(exception)}")
    end

    Process.send_after(self(), :run, state.interval)
    {:noreply, state}
  end

  defp retention_days, do: max(Application.get_env(:backend, :message_retention_days, 30), 2)
end
