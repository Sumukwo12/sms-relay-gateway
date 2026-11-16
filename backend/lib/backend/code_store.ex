defmodule Backend.CodeStore do
  @moduledoc """
  SQLite-backed store for verification codes, so codes survive a restart
  together with the queued OTP SMS that carry them.

  Codes are scoped to the system that requested them (`client`; the public
  demo API uses `"public"`): one system can neither verify nor overwrite
  another system's code for the same number. Only an HMAC of the code is
  stored.

  Codes are consumed (deleted) immediately on successful verification
  so they cannot be reused. After :max_verify_attempts wrong guesses
  (default 5) the code is discarded, which stops brute-forcing.
  """

  import Ecto.Query
  require Logger
  alias Backend.{PhoneUtils, Repo}

  defmodule OtpCode do
    @moduledoc false
    use Ecto.Schema

    @timestamps_opts [type: :utc_datetime_usec]

    schema "otp_codes" do
      field(:client, :string)
      field(:phone, :string)
      field(:code_hash, :string)
      field(:attempts, :integer, default: 0)
      field(:expires_at, :utc_datetime_usec)
      timestamps()
    end
  end

  @doc "Store a verification code for `client` and `phone`, replacing any earlier one."
  @spec put(String.t(), String.t(), String.t(), pos_integer()) :: :ok
  def put(client, phone, code, ttl_seconds) do
    now = now()

    Repo.insert!(
      %OtpCode{
        client: client,
        phone: phone,
        code_hash: hash(client, phone, code),
        attempts: 0,
        expires_at: DateTime.add(now, ttl_seconds, :second)
      },
      on_conflict: {:replace, [:code_hash, :attempts, :expires_at, :updated_at]},
      conflict_target: [:client, :phone]
    )

    Logger.debug("[CodeStore] Stored code for #{PhoneUtils.mask(phone)} TTL=#{ttl_seconds}s")
    :ok
  end

  @doc """
  Verify a submitted code against the stored code.

  Wrong guesses are counted with an atomic increment, so concurrent guesses
  cannot slip past the attempt limit.

  Returns:
    - `:ok`                           — matched; entry deleted (one-time use)
    - `{:error, :invalid_code}`       — wrong code
    - `{:error, :too_many_attempts}`  — wrong code and attempts exhausted; entry deleted
    - `{:error, :expired_or_missing}` — no active code found
    - `{:error, :cache_error}`        — storage failure
  """
  @spec verify(String.t(), String.t(), String.t()) ::
          :ok
          | {:error, :invalid_code | :too_many_attempts | :expired_or_missing | :cache_error}
  def verify(client, phone, submitted) when is_binary(submitted) do
    masked_phone = PhoneUtils.mask(phone)

    case active(client, phone) do
      nil ->
        {:error, :expired_or_missing}

      %OtpCode{} = entry ->
        this_code = from(c in OtpCode, where: c.id == ^entry.id)

        if Plug.Crypto.secure_compare(
             entry.code_hash,
             hash(client, phone, String.trim(submitted))
           ) do
          # Deleting is the claim: of two concurrent correct guesses, one wins
          case Repo.delete_all(this_code) do
            {1, _} ->
              Logger.info("[CodeStore] Code verified for #{masked_phone}")
              :ok

            _ ->
              {:error, :expired_or_missing}
          end
        else
          # Atomic increment, so concurrent wrong guesses are each counted
          case Repo.update_all(select(this_code, [c], c.attempts), inc: [attempts: 1]) do
            {1, [attempts]} ->
              if attempts >= max_attempts() do
                Repo.delete_all(this_code)

                Logger.warning(
                  "[CodeStore] Too many invalid attempts for #{masked_phone}; code discarded"
                )

                {:error, :too_many_attempts}
              else
                Logger.warning("[CodeStore] Invalid code attempt #{attempts} for #{masked_phone}")
                {:error, :invalid_code}
              end

            _ ->
              {:error, :expired_or_missing}
          end
        end
    end
  rescue
    exception in [DBConnection.ConnectionError, Exqlite.Error] ->
      Logger.error("[CodeStore] Storage error: #{Exception.message(exception)}")
      {:error, :cache_error}
  end

  @doc "Returns true if a pending code exists for this client and phone number."
  @spec has_pending?(String.t(), String.t()) :: boolean()
  def has_pending?(client, phone), do: active(client, phone) != nil

  @doc "Manually remove a code (e.g. the SMS carrying it could not be sent)."
  @spec delete(String.t(), String.t()) :: :ok
  def delete(client, phone) do
    Repo.delete_all(from(c in OtpCode, where: c.client == ^client and c.phone == ^phone))
    :ok
  end

  @doc "Delete expired codes. Returns how many were removed."
  @spec purge_expired() :: non_neg_integer()
  def purge_expired do
    now = now()
    {count, _} = Repo.delete_all(from(c in OtpCode, where: c.expires_at <= ^now))
    count
  end

  defp active(client, phone) do
    now = now()

    Repo.one(
      from(c in OtpCode,
        where: c.client == ^client and c.phone == ^phone and c.expires_at > ^now
      )
    )
  end

  # Keyed with the server secret: a leaked database alone doesn't reveal codes
  defp hash(client, phone, code) do
    secret = Application.get_env(:backend, BackendWeb.Endpoint)[:secret_key_base] || ""

    :crypto.mac(:hmac, :sha256, secret, Enum.join([client, phone, code], <<0>>))
    |> Base.encode16(case: :lower)
  end

  defp max_attempts, do: Application.get_env(:backend, :max_verify_attempts, 5)
  defp now, do: DateTime.utc_now()
end
