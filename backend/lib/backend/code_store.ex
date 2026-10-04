defmodule Backend.CodeStore do
  @moduledoc """
  Cachex-backed store for verification codes.

  Key:   phone number (E.164, e.g. "+254712345678")
  Value: %{code: "483921", attempts: 0}
  TTL:   configured :code_ttl_seconds (default 300s / 5 min)

  Codes are consumed (deleted) immediately on successful verification
  so they cannot be reused. After :max_verify_attempts wrong guesses
  (default 5) the code is discarded, which stops brute-forcing.
  """

  require Logger

  @cache :code_store

  @doc "Store a verification code for a phone number with automatic TTL expiry."
  @spec put(String.t(), String.t(), pos_integer()) :: :ok
  def put(phone, code, ttl_seconds) do
    {:ok, _} = Cachex.put(@cache, phone, %{code: code, attempts: 0}, ttl: ttl_seconds * 1_000)
    Logger.debug("[CodeStore] Stored code for #{phone} TTL=#{ttl_seconds}s")
    :ok
  end

  @doc """
  Verify a submitted code against the stored code.

  Returns:
    - `:ok`                           — matched; entry deleted (one-time use)
    - `{:error, :invalid_code}`       — wrong code
    - `{:error, :too_many_attempts}`  — wrong code and attempts exhausted; entry deleted
    - `{:error, :expired_or_missing}` — no active code found
    - `{:error, :cache_error}`        — storage failure
  """
  @spec verify(String.t(), String.t()) ::
          :ok
          | {:error, :invalid_code | :too_many_attempts | :expired_or_missing | :cache_error}
  def verify(phone, submitted) do
    case Cachex.get(@cache, phone) do
      {:ok, nil} ->
        {:error, :expired_or_missing}

      {:ok, %{code: stored, attempts: attempts}} ->
        if Plug.Crypto.secure_compare(stored, String.trim(submitted)) do
          Cachex.del(@cache, phone)
          Logger.info("[CodeStore] Code verified for #{phone}")
          :ok
        else
          record_failed_attempt(phone, stored, attempts + 1)
        end

      {:error, reason} ->
        Logger.error("[CodeStore] Cache error: #{inspect(reason)}")
        {:error, :cache_error}
    end
  end

  @doc "Returns true if a pending code exists for this phone number."
  @spec has_pending?(String.t()) :: boolean()
  def has_pending?(phone) do
    case Cachex.get(@cache, phone) do
      {:ok, nil} -> false
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc "Manually remove a code (e.g. user requests a resend)."
  @spec delete(String.t()) :: :ok
  def delete(phone) do
    Cachex.del(@cache, phone)
    :ok
  end

  defp record_failed_attempt(phone, code, attempts) do
    if attempts >= max_attempts() do
      Cachex.del(@cache, phone)
      Logger.warning("[CodeStore] Too many invalid attempts for #{phone}; code discarded")
      {:error, :too_many_attempts}
    else
      # Cachex.update/3 keeps the existing TTL
      Cachex.update(@cache, phone, %{code: code, attempts: attempts})
      Logger.warning("[CodeStore] Invalid code attempt #{attempts} for #{phone}")
      {:error, :invalid_code}
    end
  end

  defp max_attempts, do: Application.get_env(:backend, :max_verify_attempts, 5)
end
