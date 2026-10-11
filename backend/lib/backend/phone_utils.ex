defmodule Backend.PhoneUtils do
  @moduledoc """
  Utility functions for phone number processing and privacy masking.
  """

  @doc """
  Masks a phone number for safe logging, preserving country code and last 3 digits.

  ## Examples

      iex> Backend.PhoneUtils.mask("+254712345535")
      "+2547•••••535"

      iex> Backend.PhoneUtils.mask("+12025550123")
      "+1•••••••123"

      iex> Backend.PhoneUtils.mask("+447911123456")
      "+44••••••456"
  """
  @spec mask(String.t() | term()) :: String.t()
  def mask(phone) when is_binary(phone) do
    cleaned = String.replace(phone, ~r/[\s\-().]/, "")
    len = String.length(cleaned)

    if len >= 7 and String.starts_with?(cleaned, "+") do
      prefix_len = prefix_length(cleaned)
      suffix_len = 3
      mask_len = max(len - prefix_len - suffix_len, 0)

      String.slice(cleaned, 0, prefix_len) <>
        String.duplicate("•", mask_len) <>
        String.slice(cleaned, -suffix_len, suffix_len)
    else
      if len > 4 do
        String.slice(cleaned, 0, 2) <>
          String.duplicate("•", max(len - 4, 0)) <>
          String.slice(cleaned, -2, 2)
      else
        cleaned
      end
    end
  end

  def mask(other), do: inspect(other)

  # Determines the prefix length to keep for the country code / dialing prefix.
  # For Kenya (+254...), keep 5 chars (e.g. "+2547") to match "+2547•••••535"
  # For 1-digit CC (+1 US/CA, +7 RU/KZ): keep 2 chars ("+1")
  # For 2-digit CC (+44, +27, etc.): keep 3 chars ("+44")
  # For 3-digit CC: keep 4 chars
  defp prefix_length("+" <> rest = phone) do
    cond do
      String.starts_with?(phone, "+254") ->
        5

      String.starts_with?(rest, ["1", "7"]) ->
        2

      match_2_digit_cc?(rest) ->
        3

      true ->
        4
    end
  end

  defp match_2_digit_cc?(<<d1::binary-size(1), d2::binary-size(1), _::binary>>) do
    cc = d1 <> d2

    cc in [
      "20",
      "27",
      "30",
      "31",
      "32",
      "33",
      "34",
      "36",
      "39",
      "40",
      "41",
      "43",
      "44",
      "45",
      "46",
      "47",
      "48",
      "49",
      "51",
      "52",
      "53",
      "54",
      "55",
      "56",
      "57",
      "58",
      "60",
      "61",
      "62",
      "63",
      "64",
      "65",
      "66",
      "81",
      "82",
      "83",
      "84",
      "86",
      "90",
      "91",
      "92",
      "93",
      "94",
      "95",
      "98"
    ]
  end

  defp match_2_digit_cc?(_), do: false
end
