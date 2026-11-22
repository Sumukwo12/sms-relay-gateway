defmodule Backend.SmsGateway do
  @moduledoc """
  Main orchestrator for the SMS verification flow.

  Wires together: phone validation → rate limiting →
  code generation → code storage → modem delivery.

  ## Usage

      # 1. Send a code
      case Backend.SmsGateway.send_verification_code("+254712345678", client_ip: "192.168.1.100") do
        {:ok, :sent}                         -> # success
        {:error, :invalid_phone}             -> # bad number format
        {:error, :rate_limited, retry_secs}  -> # too many sends
        {:error, :modem_disconnected}        -> # USB modem not connected
        {:error, :modem_busy}                -> # modem still sending
        {:error, :modem_error, reason}       -> # modem-level failure
      end

      # 2. Verify a submitted code
      case Backend.SmsGateway.verify_code("+254712345678", "483921") do
        :ok                           -> # verified
        {:error, :invalid_code}       -> # wrong code
        {:error, :expired_or_missing} -> # expired or not sent
      end
  """

  require Logger

  alias Backend.{
    CodeGenerator,
    CodeStore,
    Messages,
    Modem,
    Outbox,
    PhoneUtils,
    RateLimiter,
    Segments
  }

  # Codes requested through the unauthenticated demo API belong to this client
  @public_client "public"

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc "Generate and send a verification code via the configured modem adapter."
  @spec send_verification_code(String.t(), String.t() | keyword() | map() | nil) ::
          {:ok, :sent}
          | {:error, :invalid_phone}
          | {:error, :rate_limited, non_neg_integer()}
          | {:error, :daily_limit_reached}
          | {:error, :modem_disconnected}
          | {:error, :modem_busy}
          | {:error, :modem_error, term()}
  def send_verification_code(phone_number, opts_or_ip \\ nil) do
    client_ip =
      cond do
        is_binary(opts_or_ip) -> opts_or_ip
        is_list(opts_or_ip) -> Keyword.get(opts_or_ip, :client_ip)
        is_map(opts_or_ip) -> Map.get(opts_or_ip, :client_ip) || Map.get(opts_or_ip, "client_ip")
        true -> nil
      end

    with {:ok, phone} <- validate_phone(phone_number),
         code = CodeGenerator.generate(),
         :ok <- check_capacity(Segments.count(render_message(code))),
         {:ok, reservation} <- RateLimiter.reserve(phone, client_ip),
         :ok <- store_code(@public_client, phone, code) do
      case deliver_sms(phone, code) do
        :ok ->
          Messages.record_direct_send(@public_client, "otp", phone, render_message(code))
          Logger.info("[Gateway] Code sent to #{PhoneUtils.mask(phone)}")
          {:ok, :sent}

        {:error, reason} = err ->
          # Send failed; release reserved rate limit slot
          RateLimiter.release(reservation)
          wrap_modem_error(err, reason)
      end
    else
      {:error, :invalid_phone} = err -> err
      {:error, :daily_limit_reached} = err -> err
      {:error, :rate_limited, _} = err -> err
      {:error, reason} -> wrap_modem_error({:error, reason}, reason)
    end
  end

  @doc """
  Generate a verification code and queue it in the outbox on behalf of an
  integrated system (`client`). Unlike `send_verification_code/2` this
  returns as soon as the message is queued; the queued SMS expires with the
  code, so a code is never delivered after it stopped being valid.

  With `:idempotency_key`, a repeated request returns `{:existing, message}`
  for the code already queued instead of sending a new one.
  """
  @spec queue_verification_code(String.t(), String.t(), keyword()) ::
          {:ok, Backend.Messages.Message.t()}
          | {:existing, Backend.Messages.Message.t()}
          | {:error, :invalid_phone}
          | {:error, :rate_limited, non_neg_integer()}
          | {:error, :daily_limit_reached}
          | {:error, {:invalid, atom(), String.t()}}
  def queue_verification_code(phone_number, client, opts \\ []) do
    key = opts[:idempotency_key]

    # A malformed key is rejected by Messages.enqueue/3
    with nil <- if(is_binary(key), do: Messages.get_by_idempotency_key(client, key)),
         {:ok, phone} <- validate_phone(phone_number),
         code = CodeGenerator.generate(),
         body = render_message(code),
         :ok <- check_capacity(Segments.count(body)),
         {:ok, reservation} <- RateLimiter.reserve(phone, nil) do
      attrs = %{
        to: phone,
        body: body,
        reference: opts[:reference],
        callback_url: opts[:callback_url]
      }

      enqueue_opts = [kind: "otp", ttl_seconds: code_ttl_seconds(), idempotency_key: key]

      # Queue first, then store the code: if a racing duplicate request won,
      # the code its SMS carries must stay the valid one.
      case Messages.enqueue(client, attrs, enqueue_opts) do
        {:ok, message} ->
          :ok = store_code(client, phone, code)
          Outbox.kick()
          {:ok, message}

        {:existing, message} ->
          RateLimiter.release(reservation)
          {:existing, message}

        {:error, field, reason} ->
          RateLimiter.release(reservation)
          {:error, {:invalid, field, reason}}
      end
    else
      %Messages.Message{} = existing -> {:existing, existing}
      error -> error
    end
  end

  @doc """
  Verify a code submitted by the user. Only codes requested by the same
  `client` match (default: the public demo API).
  """
  @spec verify_code(String.t(), String.t(), String.t()) ::
          :ok
          | {:error, :invalid_code}
          | {:error, :too_many_attempts}
          | {:error, :expired_or_missing}
          | {:error, :cache_error}
  def verify_code(phone_number, code, client \\ @public_client)

  def verify_code(phone_number, code, client) when is_binary(code) do
    case validate_phone(phone_number) do
      {:ok, phone} -> CodeStore.verify(client, phone, code)
      {:error, :invalid_phone} -> {:error, :expired_or_missing}
    end
  end

  def verify_code(_phone_number, _code, _client), do: {:error, :invalid_code}

  @doc "Seconds a freshly sent code stays valid."
  @spec code_ttl_seconds() :: pos_integer()
  def code_ttl_seconds, do: Application.get_env(:backend, :code_ttl_seconds, 300)

  @doc "Current modem status atom (:ready | :busy | :disconnected)."
  def modem_status, do: Modem.status()

  @doc "Whether a pending (unverified) code exists for this phone."
  def has_pending_code?(phone_number, client \\ @public_client) do
    case validate_phone(phone_number) do
      {:ok, phone} -> CodeStore.has_pending?(client, phone)
      _ -> false
    end
  end

  @doc """
  Rate limit info for a phone number:
  `{:ok, %{remaining: n, limit: n, retry_after_seconds: n}}` or `{:error, :invalid_phone}`.
  `retry_after_seconds` is 0 unless the number is currently blocked.
  """
  @spec rate_limit_info(String.t()) :: {:ok, map()} | {:error, :invalid_phone}
  def rate_limit_info(phone_number) do
    with {:ok, phone} <- validate_phone(phone_number) do
      retry_after =
        case RateLimiter.check(phone) do
          {:ok, _} -> 0
          {:error, :rate_limited, seconds} -> seconds
        end

      {:ok,
       %{
         remaining: RateLimiter.remaining(phone),
         limit: Application.get_env(:backend, :rate_limit_per_hour, 3),
         retry_after_seconds: retry_after
       }}
    end
  end

  # ── Private helpers ─────────────────────────────────────────────────────────

  defp wrap_modem_error({:error, :modem_disconnected} = err, _), do: err
  defp wrap_modem_error({:error, :modem_busy} = err, _), do: err
  defp wrap_modem_error(_err, reason), do: {:error, :modem_error, reason}

  defp validate_phone(phone) do
    with {:error, :invalid_phone} = err <- PhoneUtils.normalize(phone) do
      Logger.warning("[Gateway] Invalid phone: #{PhoneUtils.mask(phone)}")
      err
    end
  end

  defp store_code(client, phone, code), do: CodeStore.put(client, phone, code, code_ttl_seconds())

  defp check_capacity(segments) do
    if Outbox.capacity_available?(segments), do: :ok, else: {:error, :daily_limit_reached}
  end

  defp render_message(code) do
    Application.get_env(
      :backend,
      :sms_template,
      "Your verification code is: %{code}. Valid for 5 minutes."
    )
    |> String.replace("%{code}", code)
  end

  defp deliver_sms(phone, code) do
    message = render_message(code)

    case Modem.send_sms(phone, message) do
      :ok ->
        :ok

      error ->
        # Never leave a code behind that the user did not receive
        CodeStore.delete(@public_client, phone)
        error
    end
  end
end
