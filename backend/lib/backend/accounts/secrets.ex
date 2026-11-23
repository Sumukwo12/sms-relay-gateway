defmodule Backend.Accounts.Password do
  @moduledoc """
  PBKDF2-HMAC-SHA256 password hashing with OTP's `:crypto` (no native
  dependency). Stored as `pbkdf2-sha256$<iterations>$<salt>$<hash>`.
  """

  @key_length 32

  def hash(password) when is_binary(password) do
    salt = :crypto.strong_rand_bytes(16)
    iterations = iterations()
    digest = :crypto.pbkdf2_hmac(:sha256, password, salt, iterations, @key_length)
    Enum.join(["pbkdf2-sha256", iterations, b64(salt), b64(digest)], "$")
  end

  def verify(password, encoded) when is_binary(password) and is_binary(encoded) do
    with ["pbkdf2-sha256", iter, salt, digest] <- String.split(encoded, "$"),
         {iterations, ""} <- Integer.parse(iter),
         {:ok, salt} <- Base.url_decode64(salt, padding: false),
         {:ok, digest} <- Base.url_decode64(digest, padding: false) do
      candidate = :crypto.pbkdf2_hmac(:sha256, password, salt, iterations, byte_size(digest))
      Plug.Crypto.secure_compare(candidate, digest)
    else
      _ -> false
    end
  end

  def verify(_password, _encoded), do: false

  @doc "Spend the same time as a real check, so unknown emails can't be told apart."
  def no_user_verify do
    :crypto.pbkdf2_hmac(:sha256, "", "no-user-salt", iterations(), @key_length)
    false
  end

  defp iterations, do: Application.get_env(:backend, :password_iterations, 210_000)
  defp b64(bin), do: Base.url_encode64(bin, padding: false)
end

defmodule Backend.Accounts.Token do
  @moduledoc """
  Random bearer secrets (sessions, device tokens, API keys). Only their
  SHA-256 is stored: they are long and random, so a fast hash is enough and
  lets them be looked up directly.
  """

  def generate(prefix, bytes \\ 32),
    do: prefix <> Base.url_encode64(:crypto.strong_rand_bytes(bytes), padding: false)

  def hash(token) when is_binary(token),
    do: :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
end
