defmodule Backend.Webhooks do
  @moduledoc """
  Status callbacks to integrated systems.

  When a message has a `callback_url`, every status change to `sent`,
  `delivered` or `failed` is POSTed there as JSON:

      {"event": "message.delivered", "message": {...same shape as GET /v1/messages/:id...}}

  The request carries `X-Signature: sha256=<hex>`, an HMAC-SHA256 of the raw
  body keyed with the sending system's API key (server keys) or the account's
  webhook secret (user keys, shown in the dashboard), so the receiver can
  check it came from this gateway.

  Deliveries are stored in SQLite (`webhook_deliveries`) and sent by this
  process, so they survive restarts and receiver outages. They are retried
  with backoff (30s, 1m, 2m… up to 1h between tries) until the receiver
  answers 2xx or `:webhook_max_attempts` is reached; a 4xx other than 408/429
  is final. Events for one message are delivered strictly in order: a later
  event waits until the earlier one is delivered or given up.
  """

  use GenServer
  import Ecto.Query
  require Logger

  alias Backend.{Accounts, ApiKeys, Messages, Repo}
  alias Backend.Messages.Message

  defmodule Delivery do
    @moduledoc false
    use Ecto.Schema

    @timestamps_opts [type: :utc_datetime_usec]

    schema "webhook_deliveries" do
      field(:message_id, :string)
      field(:client, :string)
      field(:url, :string)
      field(:event, :string)
      field(:payload, :string)
      # pending | delivered | failed
      field(:status, :string, default: "pending")
      field(:attempts, :integer, default: 0)
      field(:last_error, :string)
      field(:next_attempt_at, :utc_datetime_usec)
      timestamps()
    end
  end

  @events %{
    "sent" => "message.sent",
    "delivered" => "message.delivered",
    "failed" => "message.failed"
  }

  @batch_size 50
  @max_concurrency 4

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Queue the webhook for the message's current status, if it has one."
  @spec notify(Message.t()) :: :ok
  def notify(%Message{callback_url: url, status: status} = message)
      when is_binary(url) and is_map_key(@events, status) do
    now = DateTime.utc_now()

    Repo.insert!(%Delivery{
      message_id: message.id,
      client: message.client,
      url: url,
      event: @events[status],
      # Snapshot now, so each event reports the status it is about
      payload: Jason.encode!(%{event: @events[status], message: Messages.to_public(message)}),
      status: "pending",
      next_attempt_at: now
    })

    kick()
  end

  def notify(_message), do: :ok

  @doc "The signature header value for `body` signed with `secret`."
  @spec sign(binary(), binary()) :: String.t()
  def sign(body, secret),
    do: "sha256=" <> Base.encode16(:crypto.mac(:hmac, :sha256, secret, body), case: :lower)

  @doc "Ask the dispatcher to send due webhooks now."
  def kick do
    if Application.get_env(:backend, :webhook_kick_enabled, true) and
         GenServer.whereis(__MODULE__),
       do: GenServer.cast(__MODULE__, :kick)

    :ok
  end

  @doc "Synchronously send every due webhook. Returns how many were attempted."
  def drain(timeout \\ 60_000), do: GenServer.call(__MODULE__, :drain, timeout)

  @doc "Webhooks still waiting to be delivered."
  @spec pending_count() :: non_neg_integer()
  def pending_count,
    do: Repo.aggregate(from(d in Delivery, where: d.status == "pending"), :count)

  @doc "Delete finished deliveries created before `cutoff`. Returns how many."
  @spec purge_finished_before(DateTime.t()) :: non_neg_integer()
  def purge_finished_before(%DateTime{} = cutoff) do
    {count, _} =
      from(d in Delivery, where: d.status != "pending" and d.inserted_at < ^cutoff)
      |> Repo.delete_all()

    count
  end

  # ── GenServer ───────────────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    poll_ms = Keyword.get(opts, :poll_ms, Application.get_env(:backend, :webhook_poll_ms))
    if poll_ms, do: send(self(), :poll)
    {:ok, %{poll_ms: poll_ms}}
  end

  @impl true
  def handle_cast(:kick, state) do
    safely(fn -> process_due() end)
    {:noreply, state}
  end

  @impl true
  def handle_call(:drain, _from, state), do: {:reply, process_due(), state}

  @impl true
  def handle_info(:poll, state) do
    safely(fn -> process_due() end)
    Process.send_after(self(), :poll, state.poll_ms)
    {:noreply, state}
  end

  # A database hiccup should cost one round, not the worker
  defp safely(fun) do
    fun.()
  rescue
    exception -> Logger.error("[Webhooks] Processing failed: #{Exception.message(exception)}")
  catch
    :exit, reason -> Logger.error("[Webhooks] Processing failed: #{inspect(reason)}")
  end

  defp process_due do
    due = due_deliveries()

    due
    |> Task.async_stream(&attempt/1,
      max_concurrency: @max_concurrency,
      timeout: :infinity,
      ordered: false
    )
    |> Stream.run()

    length(due)
  end

  # Oldest pending delivery of each message, if it is due. Later events for
  # the same message wait their turn, which keeps them in order.
  defp due_deliveries do
    now = DateTime.utc_now()

    from(d in Delivery, where: d.status == "pending", order_by: [asc: d.id])
    |> Repo.all()
    |> Enum.uniq_by(& &1.message_id)
    |> Enum.filter(&(DateTime.compare(&1.next_attempt_at, now) != :gt))
    |> Enum.take(@batch_size)
  end

  defp attempt(%Delivery{} = delivery) do
    attempts = delivery.attempts + 1

    changes =
      case post(delivery) do
        :ok ->
          [status: "delivered", attempts: attempts, last_error: nil]

        {:final, error} ->
          Logger.warning("[Webhooks] #{delivery.message_id}: giving up: #{error}")
          [status: "failed", attempts: attempts, last_error: error]

        {:retry, error} ->
          if attempts >= max_attempts() do
            Logger.warning(
              "[Webhooks] #{delivery.message_id}: giving up after #{attempts} attempts: #{error}"
            )

            [status: "failed", attempts: attempts, last_error: error]
          else
            Logger.warning("[Webhooks] #{delivery.message_id}: #{error}; retrying")
            retry_at = DateTime.add(DateTime.utc_now(), backoff_seconds(attempts), :second)
            [attempts: attempts, last_error: error, next_attempt_at: retry_at]
          end
      end

    from(d in Delivery, where: d.id == ^delivery.id)
    |> Repo.update_all(set: Keyword.put(changes, :updated_at, DateTime.utc_now()))
  end

  defp post(delivery) do
    secret =
      ApiKeys.key_for(delivery.client) || Accounts.webhook_secret_for_client(delivery.client)

    headers =
      [{"content-type", "application/json"}] ++
        if(secret, do: [{"x-signature", sign(delivery.payload, secret)}], else: [])

    options =
      [body: delivery.payload, headers: headers, retry: false, receive_timeout: 10_000]
      |> Keyword.merge(Application.get_env(:backend, :webhook_req_options, []))

    case Req.post(delivery.url, options) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: status}} when status in 400..499 and status not in [408, 429] ->
        {:final, "callback returned HTTP #{status}"}

      {:ok, %Req.Response{status: status}} ->
        {:retry, "callback returned HTTP #{status}"}

      {:error, exception} ->
        {:retry, "callback failed: " <> String.slice(Exception.message(exception), 0, 200)}
    end
  end

  # 30s, 60s, 120s, ... capped at 1 hour
  defp backoff_seconds(attempts), do: min(30 * Integer.pow(2, attempts - 1), 3_600)

  defp max_attempts, do: Application.get_env(:backend, :webhook_max_attempts, 12)
end
