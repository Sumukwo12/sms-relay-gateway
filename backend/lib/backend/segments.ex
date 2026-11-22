defmodule Backend.Segments do
  @moduledoc """
  How many SMS parts a body is sent as, which is what an SMS bundle charges.

  Bodies made only of GSM-7 characters fit 160 per SMS (153 per part once
  split, because each part carries a header); the extension characters
  `^{}\\[~]|€` and form feed take two slots. Anything else (emoji, most
  non-Latin scripts, curly quotes) switches the whole message to UCS-2:
  70 per SMS, 67 per part, counted in UTF-16 code units.
  """

  @gsm_basic ~c"@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà"
             |> MapSet.new()
  @gsm_extension ~c"\f^{}\\[~]|€" |> MapSet.new()

  @doc "Number of SMS parts `body` needs."
  @spec count(String.t()) :: pos_integer()
  def count(body) when is_binary(body) do
    case gsm_length(body) do
      {:ok, length} -> parts(length, 160, 153)
      :ucs2 -> parts(utf16_length(body), 70, 67)
    end
  end

  @doc "Whether the body can be sent in the GSM-7 alphabet."
  @spec gsm7?(String.t()) :: boolean()
  def gsm7?(body), do: match?({:ok, _}, gsm_length(body))

  defp gsm_length(body) do
    body
    |> String.to_charlist()
    |> Enum.reduce_while({:ok, 0}, fn char, {:ok, length} ->
      cond do
        MapSet.member?(@gsm_basic, char) -> {:cont, {:ok, length + 1}}
        MapSet.member?(@gsm_extension, char) -> {:cont, {:ok, length + 2}}
        true -> {:halt, :ucs2}
      end
    end)
  end

  defp utf16_length(body),
    do: div(byte_size(:unicode.characters_to_binary(body, :utf8, :utf16)), 2)

  defp parts(0, _single, _multi), do: 1
  defp parts(length, single, _multi) when length <= single, do: 1
  defp parts(length, _single, multi), do: div(length + multi - 1, multi)
end
