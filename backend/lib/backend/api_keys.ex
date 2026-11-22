defmodule Backend.ApiKeys do
  @moduledoc """
  API keys for the internal systems allowed to use the `/v1` API.

  Configured as `config :backend, api_keys: %{"system_name" => "key"}`, or
  `API_KEYS="billing:key1,crm:key2"` at boot. The system name is recorded on
  every message it sends.
  """

  @doc "The system name for a presented key, compared in constant time."
  @spec authenticate(String.t() | nil) :: {:ok, String.t()} | :error
  def authenticate(key) when is_binary(key) and key != "" do
    Enum.find_value(keys(), :error, fn {name, expected} ->
      if Plug.Crypto.secure_compare(key, expected), do: {:ok, name}
    end)
  end

  def authenticate(_), do: :error

  @doc "The key configured for a system name, or nil."
  @spec key_for(String.t()) :: String.t() | nil
  def key_for(name), do: Map.get(keys(), name)

  @doc "Whether any keys are configured."
  def configured?, do: map_size(keys()) > 0

  defp keys, do: Application.get_env(:backend, :api_keys, %{})
end
