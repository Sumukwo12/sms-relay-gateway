defmodule BackendWeb.V1.Owner do
  @moduledoc false
  # Who a /v1 request sends as: the key's user (their phones, their limits)
  # or the server. An optional `device_id` picks one of the user's phones.

  alias Backend.Accounts
  alias BackendWeb.V1.Errors

  @doc "Owner options for `Backend.SmsGateway`, or a halted 422 response."
  def opts(conn, params) do
    user = conn.assigns[:api_user]

    base = [
      user: user,
      api_key_id: conn.assigns[:api_key_id],
      test: conn.assigns[:api_test] == true
    ]

    case {user, params["device_id"]} do
      {_, nil} ->
        {:ok, base}

      {nil, _} ->
        Errors.invalid(conn, :device_id, "is only available with a user API key")

      {user, device_id} ->
        case Accounts.get_device(user.id, device_id) do
          nil -> Errors.invalid(conn, :device_id, "is not one of your linked phones")
          device -> {:ok, [{:device_id, device.id} | base]}
        end
    end
  end
end
