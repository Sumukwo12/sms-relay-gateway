defmodule Backend.Messages do
  @moduledoc """
  Persistent outbox of SMS messages sent on behalf of integrated systems.

  Messages are enqueued by the `/v1` API and delivered one at a time by
  `Backend.Outbox`. Every state change goes through this module, which also
  fires webhooks (`Backend.Webhooks`) when a message is sent, delivered or
  fails.
  """

  import Ecto.Query
  require Logger

  alias Backend.{PhoneUtils, Repo, Segments, Webhooks}
  alias Backend.Messages.Message

  # Matches the SMS Relay app's own body limit (3 concatenated SMS parts).
  @max_body_length 480
  @max_reference_length 100
  @max_idempotency_key_length 100

  # ── Enqueue / read ──────────────────────────────────────────────────────────

  @doc """
  Validate and queue a message for `client`.

  Attrs (string or atom keys): `to`, `body`, and optionally `reference`,
  `callback_url`. Options: `:kind` (`"notification"` | `"otp"`),
  `:ttl_seconds` (how long it may wait in the queue), `:idempotency_key`,
  and the owner: `:user_id` (nil = server-level), `:device_id` (send through
  this phone only) and `:api_key_id`.

  Returns `{:ok, message}`, `{:existing, message}` when `client` already
  queued a message with the same idempotency key (nothing new is queued), or
  `{:error, field, reason}`.
  """
  @spec enqueue(String.t(), map(), keyword()) ::
          {:ok, Message.t()} | {:existing, Message.t()} | {:error, atom(), String.t()}
  def enqueue(client, attrs, opts \\ []) when is_binary(client) do
    now = now()
    ttl = Keyword.get(opts, :ttl_seconds, Application.get_env(:backend, :message_ttl_seconds))

    with {:ok, key} <- validate_idempotency_key(opts[:idempotency_key]),
         nil <- key && get_by_idempotency_key(client, key),
         {:ok, to} <- validate_to(get(attrs, :to)),
         {:ok, body} <- validate_body(get(attrs, :body)),
         {:ok, reference} <- validate_reference(get(attrs, :reference)),
         {:ok, callback_url} <- validate_callback_url(get(attrs, :callback_url)) do
      message = %Message{
        id: generate_id(),
        client: client,
        kind: Keyword.get(opts, :kind, "notification"),
        to: to,
        body: body,
        segments: Segments.count(body),
        status: "queued",
        attempts: 0,
        max_attempts: Application.get_env(:backend, :message_max_attempts, 3),
        reference: reference,
        callback_url: callback_url,
        idempotency_key: key,
        next_attempt_at: now,
        expires_at: DateTime.add(now, ttl, :second),
        user_id: opts[:user_id],
        device_id: opts[:device_id],
        api_key_id: opts[:api_key_id]
      }

      insert_new(message)
    else
      %Message{} = existing -> {:existing, existing}
      error -> error
    end
  end

  # Two requests racing with the same idempotency key: the unique index lets
  # one insert win and the other gets its message back.
  defp insert_new(message) do
    message = Repo.insert!(message)

    Logger.info(
      "[Messages] Queued #{message.kind} #{message.id} for #{PhoneUtils.mask(message.to)} (client=#{message.client})"
    )

    {:ok, message}
  rescue
    error in Ecto.ConstraintError ->
      case message.idempotency_key &&
             get_by_idempotency_key(message.client, message.idempotency_key) do
        %Message{} = existing -> {:existing, existing}
        _ -> reraise error, __STACKTRACE__
      end
  end

  @doc """
  Record an SMS that was sent directly through the modem (the public demo
  API) so it counts toward the daily cap. Its body is not kept.
  """
  @spec record_direct_send(String.t(), String.t(), String.t(), String.t()) :: Message.t()
  def record_direct_send(client, kind, to, body) do
    now = now()

    Repo.insert!(%Message{
      id: generate_id(),
      client: client,
      kind: kind,
      to: to,
      body: "[redacted]",
      segments: Segments.count(body),
      status: "sent",
      attempts: 1,
      max_attempts: 1,
      next_attempt_at: now,
      expires_at: now,
      sent_at: now
    })
  end

  @doc "The message `client` queued with this idempotency key, if any."
  @spec get_by_idempotency_key(String.t(), String.t()) :: Message.t() | nil
  def get_by_idempotency_key(client, key) when is_binary(key) do
    Repo.one(from(m in Message, where: m.client == ^client and m.idempotency_key == ^key))
  end

  @doc "Fetch a message, scoped to the client that created it."
  @spec get_for_client(String.t(), String.t()) :: Message.t() | nil
  def get_for_client(client, id) when is_binary(id) do
    Repo.one(from(m in Message, where: m.id == ^id and m.client == ^client))
  end

  @doc "Fetch a message by id (any client)."
  def get(id) when is_binary(id), do: Repo.get(Message, id)

  # Counters below take a scope: `:system` (server-level messages, user_id
  # nil — the default, as before accounts existed), a user id, or `:all`.

  @doc "Messages waiting to be sent."
  @spec queue_depth(scope()) :: non_neg_integer()
  def queue_depth(scope \\ :system) do
    from(m in Message, where: m.status in ["queued", "sending"])
    |> scoped(scope)
    |> Repo.aggregate(:count)
  end

  @doc "SMS parts waiting to be sent (for the daily cap)."
  @spec queued_segments(scope()) :: non_neg_integer()
  def queued_segments(scope \\ :system) do
    from(m in Message, where: m.status in ["queued", "sending"])
    |> scoped(scope)
    |> Repo.aggregate(:sum, :segments) || 0
  end

  @doc """
  SMS parts that left the phone in the last 24 hours (for the daily cap).
  A long message counts once per part, as the SMS bundle charges it.
  """
  @spec sent_last_24h(scope()) :: non_neg_integer()
  def sent_last_24h(scope \\ :system) do
    since = DateTime.add(now(), -86_400, :second)

    from(m in Message, where: m.sent_at > ^since)
    |> scoped(scope)
    |> Repo.aggregate(:sum, :segments) || 0
  end

  @doc "SMS parts each user sent in the last 24 hours, as `%{user_id => parts}`."
  @spec sent_by_user_last_24h() :: %{pos_integer() => non_neg_integer()}
  def sent_by_user_last_24h do
    since = DateTime.add(now(), -86_400, :second)

    from(m in Message,
      where: m.sent_at > ^since and not is_nil(m.user_id),
      group_by: m.user_id,
      select: {m.user_id, sum(m.segments)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc "When the oldest message still waiting to be sent was queued, or nil."
  @spec oldest_queued_at(scope()) :: DateTime.t() | nil
  def oldest_queued_at(scope \\ :system) do
    from(m in Message, where: m.status in ["queued", "sending"], select: min(m.inserted_at))
    |> scoped(scope)
    |> Repo.one()
  end

  @doc "A user's most recent messages, newest first."
  @spec list_for_user(pos_integer(), pos_integer()) :: [Message.t()]
  def list_for_user(user_id, limit \\ 100) do
    from(m in Message,
      where: m.user_id == ^user_id,
      order_by: [desc: m.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc "The most recent messages of everyone (admin monitoring), newest first."
  @spec list_recent(pos_integer()) :: [Message.t()]
  def list_recent(limit \\ 200) do
    from(m in Message, order_by: [desc: m.inserted_at], limit: ^limit) |> Repo.all()
  end

  @type scope :: :system | :all | pos_integer()

  defp scoped(query, :all), do: query
  defp scoped(query, :system), do: where(query, [m], is_nil(m.user_id))

  defp scoped(query, user_id) when is_integer(user_id),
    do: where(query, [m], m.user_id == ^user_id)

  @doc "JSON-friendly view of a message. Never includes the body."
  @spec to_public(Message.t()) :: map()
  def to_public(%Message{} = m) do
    %{
      id: m.id,
      kind: m.kind,
      to: m.to,
      status: m.status,
      attempts: m.attempts,
      error: m.last_error,
      reference: m.reference,
      segments: m.segments,
      device_id: m.device_id,
      created_at: m.inserted_at,
      sent_at: m.sent_at,
      delivered_at: m.delivered_at,
      failed_at: m.failed_at,
      expires_at: m.expires_at
    }
  end

  # ── Outbox state transitions ───────────────────────────────────────────────

  @doc """
  Claim the oldest due message for sending: marks it `sending` and counts an
  attempt. Returns `nil` when nothing is due.

  `routing` limits it to messages that can go out now:
  `%{owners: :any | %{users: MapSet, system: boolean}, blocked: [user_id], system_ok: boolean}`
  — owners with a phone online, minus users who may not send (not approved
  or over their daily limit); `system_ok` is false once the server-level
  daily cap is reached. `:any` (the default) takes any due message.
  """
  @spec checkout_next(:any | map()) :: Message.t() | nil
  def checkout_next(routing \\ :any) do
    now = now()

    query =
      from(m in Message,
        where: m.status == "queued" and m.next_attempt_at <= ^now and m.expires_at > ^now,
        order_by: [asc: m.inserted_at],
        limit: 1
      )
      |> routed(routing)

    with %Message{} = message <- Repo.one(query),
         {1, _} <-
           from(m in Message, where: m.id == ^message.id and m.status == "queued")
           |> Repo.update_all(
             set: [status: "sending", attempts: message.attempts + 1, updated_at: now]
           ) do
      get(message.id)
    else
      # Nothing due, or a phone report changed the message under us
      _ -> nil
    end
  end

  defp routed(query, :any), do: query

  defp routed(query, %{owners: owners, blocked: blocked, system_ok: system_ok}) do
    system? = system_ok and (owners == :any or owners.system)

    users =
      case owners do
        :any -> dynamic([m], not is_nil(m.user_id) and m.user_id not in ^blocked)
        %{users: ids} -> dynamic([m], m.user_id in ^(MapSet.to_list(ids) -- blocked))
      end

    condition = if system?, do: dynamic([m], is_nil(m.user_id) or ^users), else: users
    where(query, ^condition)
  end

  @doc "When the next queued message becomes due, or nil if none are waiting."
  @spec next_due_at() :: DateTime.t() | nil
  def next_due_at do
    Repo.one(
      from(m in Message,
        where: m.status == "queued",
        select: min(m.next_attempt_at)
      )
    )
  end

  @doc "The phone accepted and sent the message."
  def mark_sent(%Message{} = message), do: mark_sent(message.id)

  def mark_sent(id) when is_binary(id) do
    transition(id, ~w(queued sending failed), fn m ->
      [status: "sent", sent_at: now(), last_error: nil, failed_at: nil]
      |> redact_body(m)
    end)
  end

  @doc "The carrier confirmed delivery to the handset."
  def mark_delivered(id) when is_binary(id) do
    transition(id, ~w(queued sending sent failed), fn m ->
      [status: "delivered", delivered_at: now(), sent_at: m.sent_at || now(), last_error: nil]
      |> redact_body(m)
    end)
  end

  @doc """
  A send attempt failed. Retries with exponential backoff while attempts
  remain and the message has not expired; otherwise marks it failed.
  """
  def attempt_failed(%Message{} = message, error) do
    error = format_error(error)
    now = now()
    retry_at = DateTime.add(now, backoff_seconds(message.attempts), :second)

    if message.attempts < message.max_attempts and
         DateTime.compare(retry_at, message.expires_at) == :lt do
      Logger.warning(
        "[Messages] Attempt #{message.attempts}/#{message.max_attempts} failed for #{message.id}: #{error}; retrying"
      )

      transition(message.id, ~w(sending), fn _ ->
        [status: "queued", next_attempt_at: retry_at, last_error: error]
      end)
    else
      fail(message.id, error)
    end
  end

  @doc """
  The phone was unreachable, so nothing was attempted. Puts the message back
  in the queue without counting the attempt.
  """
  def defer(%Message{} = message, error, retry_in_seconds) do
    transition(message.id, ~w(sending), fn m ->
      [
        status: "queued",
        attempts: max(m.attempts - 1, 0),
        next_attempt_at: DateTime.add(now(), retry_in_seconds, :second),
        last_error: format_error(error)
      ]
    end)
  end

  @doc "Permanently fail a message (no further attempts)."
  def fail(id, error) when is_binary(id) do
    error = format_error(error)
    Logger.warning("[Messages] Message #{id} failed: #{error}")

    transition(id, ~w(queued sending), fn m ->
      [status: "failed", failed_at: now(), last_error: error] |> redact_body(m)
    end)
  end

  @doc """
  Apply a result the phone reported for a message, even if the outbox has
  already given up waiting for it (late results after a timeout).
  """
  def apply_phone_result(id, "sent", _error), do: mark_sent(id)
  def apply_phone_result(_id, _status, _error), do: :ignored

  @doc "Fail every queued message whose time in the queue ran out."
  @spec expire_stale() :: non_neg_integer()
  def expire_stale do
    now = now()

    from(m in Message, where: m.status == "queued" and m.expires_at <= ^now, select: m.id)
    |> Repo.all()
    |> Enum.count(fn id -> match?({:ok, _}, fail(id, "expired")) end)
  end

  @doc """
  Return messages stuck in `sending` (the server stopped mid-send) to the
  queue. The phone ignores ids it has already sent, so this cannot double-send
  while the phone app keeps running.
  """
  @spec requeue_interrupted() :: non_neg_integer()
  def requeue_interrupted do
    {count, _} =
      from(m in Message, where: m.status == "sending")
      |> Repo.update_all(set: [status: "queued", next_attempt_at: now(), updated_at: now()])

    if count > 0, do: Logger.warning("[Messages] Requeued #{count} interrupted message(s)")
    count
  end

  @doc """
  Delete finished messages (sent, delivered or failed) created before
  `cutoff`. Returns how many were removed.
  """
  @spec purge_finished_before(DateTime.t()) :: non_neg_integer()
  def purge_finished_before(%DateTime{} = cutoff) do
    {count, _} =
      from(m in Message,
        where: m.status in ["sent", "delivered", "failed"] and m.inserted_at < ^cutoff
      )
      |> Repo.delete_all()

    count
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  # Applies `changes_fun` only while the message is in one of `from_statuses`,
  # then notifies the client's webhook when the status changed. The update is
  # conditional on the status it read, so when the outbox and a late phone
  # report race to apply the same transition, only one wins (one webhook).
  defp transition(id, from_statuses, changes_fun) do
    case get(id) do
      nil ->
        {:error, :not_found}

      %Message{status: status} = message ->
        if status in from_statuses do
          changes = Keyword.put(changes_fun.(message), :updated_at, now())

          {count, _} =
            from(m in Message, where: m.id == ^id and m.status == ^status)
            |> Repo.update_all(set: changes)

          if count == 1 do
            updated = get(id)
            if updated.status != status, do: Webhooks.notify(updated)
            {:ok, updated}
          else
            {:error, :conflict}
          end
        else
          {:error, {:invalid_transition, status}}
        end
    end
  end

  # Bodies are only needed to send: once a message is done, drop its body
  # (OTP codes are secrets, notifications may hold personal data).
  defp redact_body(changes, _message), do: Keyword.put(changes, :body, "[redacted]")

  # 15s, 30s, 60s, ... capped at 5 minutes
  defp backoff_seconds(attempts), do: min(15 * Integer.pow(2, max(attempts - 1, 0)), 300)

  defp validate_to(to) do
    case PhoneUtils.normalize(to) do
      {:ok, phone} ->
        {:ok, phone}

      {:error, :invalid_phone} ->
        {:error, :to, "must be an E.164 phone number, e.g. +254712345678"}
    end
  end

  defp validate_body(body) when is_binary(body) do
    body = String.trim(body)

    cond do
      body == "" ->
        {:error, :body, "must not be empty"}

      String.length(body) > @max_body_length ->
        {:error, :body, "must be at most #{@max_body_length} characters"}

      Segments.count(body) > max_segments() ->
        {:error, :body,
         "must fit in #{max_segments()} SMS parts (#{max_segments() * 67} characters when it contains emoji or non-Latin text)"}

      true ->
        {:ok, body}
    end
  end

  defp validate_body(_), do: {:error, :body, "is required"}

  defp validate_reference(nil), do: {:ok, nil}

  defp validate_reference(ref) when is_binary(ref) and byte_size(ref) <= @max_reference_length,
    do: {:ok, ref}

  defp validate_reference(_),
    do: {:error, :reference, "must be a string of at most #{@max_reference_length} characters"}

  defp validate_idempotency_key(nil), do: {:ok, nil}

  defp validate_idempotency_key(key)
       when is_binary(key) and key != "" and byte_size(key) <= @max_idempotency_key_length,
       do: {:ok, key}

  defp validate_idempotency_key(_),
    do:
      {:error, :idempotency_key,
       "must be a non-empty string of at most #{@max_idempotency_key_length} characters"}

  defp max_segments, do: Application.get_env(:backend, :message_max_segments, 4)

  defp validate_callback_url(nil), do: {:ok, nil}

  defp validate_callback_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        {:ok, url}

      _ ->
        {:error, :callback_url, "must be an http(s) URL"}
    end
  end

  defp validate_callback_url(_), do: {:error, :callback_url, "must be an http(s) URL"}

  defp get(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

  defp format_error(error) when is_binary(error), do: String.slice(error, 0, 255)
  defp format_error(error) when is_atom(error), do: Atom.to_string(error)
  defp format_error(error), do: error |> inspect() |> String.slice(0, 255)

  defp generate_id, do: "msg_" <> Base.encode16(:crypto.strong_rand_bytes(10), case: :lower)

  defp now, do: DateTime.utc_now()
end
