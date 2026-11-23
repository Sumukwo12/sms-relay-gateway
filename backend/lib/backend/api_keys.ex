defmodule Backend.ApiKeys do
  @moduledoc """
  Authenticates `/v1` API keys. Two kinds:

    - **User keys** (`sk_…`), created in the dashboard and stored hashed
      (`Backend.Accounts`). Messages are sent through that user's phones and
      stored under the tenant `user:<id>`.
    - **Server keys** from `config :backend, api_keys: %{"system_name" => "key"}`
      (`API_KEYS="billing:key1,crm:key2"` at boot). Server-level: sent
      through the legacy/admin phone, stored under the system name.
  """

  alias Backend.Accounts
  alias Backend.Accounts.User

  @type identity :: %{
          client: String.t(),
          name: String.t(),
          user: User.t() | nil,
          api_key_id: pos_integer() | nil,
          test: boolean()
        }

  @doc "Who a presented key belongs to."
  @spec authenticate(String.t() | nil) :: {:ok, identity()} | :error
  def authenticate(key) when is_binary(key) and key != "" do
    case server_key(key) do
      {:ok, name} -> {:ok, %{client: name, name: name, user: nil, api_key_id: nil, test: false}}
      :error -> user_key(key)
    end
  end

  def authenticate(_), do: :error

  defp server_key(key) do
    Enum.find_value(keys(), :error, fn {name, expected} ->
      if Plug.Crypto.secure_compare(key, expected), do: {:ok, name}
    end)
  end

  defp user_key("sk_" <> _ = key) do
    case Accounts.authenticate_api_key(key) do
      {:ok, api_key} ->
        {:ok,
         %{
           client: User.client(api_key.user),
           name: api_key.name,
           user: api_key.user,
           api_key_id: api_key.id,
           test: api_key.mode == "test"
         }}

      :error ->
        :error
    end
  end

  defp user_key(_key), do: :error

  @doc "The server key configured for a system name, or nil."
  @spec key_for(String.t()) :: String.t() | nil
  def key_for(name), do: Map.get(keys(), name)

  @doc "Whether any server keys are configured."
  def configured?, do: map_size(keys()) > 0

  defp keys, do: Application.get_env(:backend, :api_keys, %{})
end
