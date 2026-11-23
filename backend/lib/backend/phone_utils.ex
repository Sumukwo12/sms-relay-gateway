defmodule Backend.PhoneUtils do
  @moduledoc """
  Utility functions for phone number processing and privacy masking.
  """

  @doc """
  Normalize a phone number to E.164: strips spaces, dashes, dots and
  parentheses ("+254 712-345 678" → "+254712345678"), then requires
  +<country code><subscriber>, 8-15 digits in total.

  Numbers written the local way are completed with the default country code
  (`:default_country_code`, "254" for Kenya; env `DEFAULT_COUNTRY_CODE`):
  "0712345678", "712345678", "254712345678" and "00254712345678" all become
  "+254712345678".
  """
  @spec normalize(term()) :: {:ok, String.t()} | {:error, :invalid_phone}
  def normalize(phone) when is_binary(phone) do
    cleaned = phone |> String.replace(~r/[\s\-().]/, "") |> complete_country_code()

    if Regex.match?(~r/^\+[1-9]\d{7,14}$/, cleaned),
      do: {:ok, cleaned},
      else: {:error, :invalid_phone}
  end

  def normalize(_), do: {:error, :invalid_phone}

  defp complete_country_code("+" <> _ = number), do: number
  defp complete_country_code("00" <> rest), do: "+" <> rest

  defp complete_country_code(number) do
    cc = Application.get_env(:backend, :default_country_code, "254")

    cond do
      not Regex.match?(~r/^\d+$/, number) or cc in [nil, ""] -> number
      # 0712345678 (national trunk prefix)
      String.starts_with?(number, "0") -> "+" <> cc <> String.trim_leading(number, "0")
      # 254712345678 (country code without the +)
      String.starts_with?(number, cc) and byte_size(number) > 10 -> "+" <> number
      # 712345678 (subscriber number only)
      byte_size(number) in 7..10 -> "+" <> cc <> number
      true -> number
    end
  end

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
