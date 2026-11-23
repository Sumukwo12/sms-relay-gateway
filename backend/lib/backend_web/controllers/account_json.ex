defmodule BackendWeb.AccountJSON do
  @moduledoc "JSON shapes for the dashboard, admin and app APIs."

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Backend.{Accounts, Messages}
  alias Backend.Accounts.{ApiKey, Device, User}
  alias Backend.Modem.Phone

  def user(%User{} = u) do
    %{
      id: u.id,
      email: u.email,
      name: u.name,
      role: u.role,
      status: u.status,
      daily_limit: Accounts.daily_limit(u),
      created_at: u.inserted_at
    }
  end

  def api_key(%ApiKey{} = k) do
    %{
      id: k.id,
      name: k.name,
      prefix: k.prefix,
      mode: k.mode,
      last_used_at: k.last_used_at,
      created_at: k.inserted_at
    }
  end

  @doc "A user's linked phones with live connection state."
  def devices(user_id) do
    online = online_by_device(Phone.connected(user_id))
    Enum.map(Accounts.list_devices(user_id), &device(&1, online))
  end

  def all_devices do
    online = online_by_device(Phone.connected(:all))

    Enum.map(Accounts.list_all_devices(), fn d ->
      d |> device(online) |> Map.put(:owner, %{id: d.user.id, email: d.user.email})
    end)
  end

  def device(%Device{} = d, online \\ %{}) do
    info = Map.get(online, d.id)

    %{
      id: d.id,
      name: d.name,
      model: d.model,
      app_version: d.app_version,
      online: Map.has_key?(online, d.id),
      battery: info && info["battery"],
      charging: info && info["is_charging"],
      signal: info && info["signal"],
      last_seen_at: d.last_seen_at,
      created_at: d.inserted_at
    }
  end

  # Phone.connected/1 only answers when the phone adapter is running
  defp online_by_device(connected) do
    for %{device_id: id, info: info} <- connected,
        is_integer(id),
        into: %{},
        do: {id, info || %{}}
  end

  def message(m) do
    m
    |> Messages.to_public()
    |> Map.put(:client, if(String.starts_with?(m.client, "user:"), do: nil, else: m.client))
  end

  def errors_response(conn, errors) when is_map(errors) do
    {field, message} = Enum.min_by(errors, fn {field, _} -> to_string(field) end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      success: false,
      error: "invalid_request",
      message: "#{humanize(field)} #{message}",
      field: field,
      errors: errors
    })
  end

  def error(conn, status, code, message) do
    conn |> put_status(status) |> json(%{success: false, error: code, message: message})
  end

  def halt_error(conn, status, code, message), do: conn |> error(status, code, message) |> halt()

  defp humanize(field),
    do: field |> to_string() |> String.replace("_", " ") |> String.capitalize()
end
