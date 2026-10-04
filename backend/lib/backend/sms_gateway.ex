defmodule Backend.SmsGateway do
  @moduledoc """
  Main orchestrator for the SMS verification flow.

  Wires together: phone validation → rate limiting →
  code generation → code storage → modem delivery.

  ## Usage

      # 1. Send a code
      case Backend.SmsGateway.send_verification_code("+254712345678") do
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

  alias Backend.{CodeGenerator, CodeStore, Modem, RateLimiter}

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc "Generate and send a verification code via the USB GSM modem."
  @spec send_verification_code(String.t()) ::
          {:ok, :sent}
          | {:error, :invalid_phone}
          | {:error, :rate_limited, non_neg_integer()}
          | {:error, :modem_disconnected}
          | {:error, :modem_busy}
          | {:error, :modem_error, term()}
  def send_verification_code(phone_number) do
    with {:ok, phone} <- validate_phone(phone_number),
         :ok <- check_rate_limit(phone),
         code = CodeGenerator.generate(),
         :ok <- store_code(phone, code),
         :ok <- deliver_sms(phone, code) do
      RateLimiter.record(phone)
      Logger.info("[Gateway] Code sent to #{phone}")
      {:ok, :sent}
    else
      {:error, :invalid_phone} = err -> err
      {:error, :rate_limited, _} = err -> err
      {:error, :modem_disconnected} = err -> err
      {:error, :modem_busy} = err -> err
      {:error, reason} -> {:error, :modem_error, reason}
    end
  end

  @doc "Verify a code submitted by the user."
  @spec verify_code(String.t(), String.t()) ::
          :ok
          | {:error, :invalid_code}
          | {:error, :too_many_attempts}
          | {:error, :expired_or_missing}
          | {:error, :cache_error}
  def verify_code(phone_number, code) when is_binary(code) do
    case validate_phone(phone_number) do
      {:ok, phone} -> CodeStore.verify(phone, code)
      {:error, :invalid_phone} -> {:error, :expired_or_missing}
    end
  end

  def verify_code(_phone_number, _code), do: {:error, :invalid_code}

  @doc "Seconds a freshly sent code stays valid."
  @spec code_ttl_seconds() :: pos_integer()
  def code_ttl_seconds, do: Application.get_env(:backend, :code_ttl_seconds, 300)

  @doc "Current modem status atom (:ready | :busy | :disconnected)."
  def modem_status, do: Modem.status()

  @doc "Whether a pending (unverified) code exists for this phone."
  def has_pending_code?(phone_number) do
    case validate_phone(phone_number) do
      {:ok, phone} -> CodeStore.has_pending?(phone)
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

  # E.164 format: +<1-3 digit country code><subscriber number>, total 8-15 digits.
  # Spaces, dashes, dots and parentheses are stripped first ("+254 712-345 678").
  defp validate_phone(phone) when is_binary(phone) do
    cleaned = String.replace(phone, ~r/[\s\-().]/, "")

    if Regex.match?(~r/^\+[1-9]\d{7,14}$/, cleaned) do
      {:ok, cleaned}
    else
      Logger.warning("[Gateway] Invalid phone: #{inspect(phone)}")
      {:error, :invalid_phone}
    end
  end

  defp validate_phone(phone) do
    Logger.warning("[Gateway] Invalid phone: #{inspect(phone)}")
    {:error, :invalid_phone}
  end

  defp check_rate_limit(phone) do
    case RateLimiter.check(phone) do
      {:ok, _} -> :ok
      {:error, :rate_limited, retry_after} -> {:error, :rate_limited, retry_after}
    end
  end

  defp store_code(phone, code), do: CodeStore.put(phone, code, code_ttl_seconds())

  defp deliver_sms(phone, code) do
    template =
      Application.get_env(
        :backend,
        :sms_template,
        "Your verification code is: %{code}. Valid for 5 minutes."
      )

    message = String.replace(template, "%{code}", code)

    case Modem.send_sms(phone, message) do
      :ok ->
        :ok

      error ->
        # Never leave a code behind that the user did not receive
        CodeStore.delete(phone)
        error
    end
  end
end
