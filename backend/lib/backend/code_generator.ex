defmodule Backend.CodeGenerator do
  @moduledoc """
  Generates cryptographically secure numeric verification codes
  using :crypto.strong_rand_bytes/1 (OpenSSL under the hood).
  """

  @doc """
  Generate a numeric code of `length` digits.
  Defaults to the configured :code_length (typically 6).

      iex> Backend.CodeGenerator.generate()
      "483921"
  """
  @spec generate(pos_integer() | nil) :: String.t()
  def generate(length \\ nil) do
    length = length || Application.get_env(:backend, :code_length, 6)
    max_val = :math.pow(10, length) |> round()

    :crypto.strong_rand_bytes(8)
    |> :binary.decode_unsigned()
    |> rem(max_val)
    |> Integer.to_string()
    |> String.pad_leading(length, "0")
  end
end
