defmodule BackendWeb.AdminController do
  @moduledoc """
  Administration (admins only).

    GET   /api/admin/overview   totals across the gateway
    GET   /api/admin/users      every account with its usage
    PATCH /api/admin/users/:id  {status?, role?, daily_limit?}
    GET   /api/admin/devices    every linked phone
  """

  use BackendWeb, :controller

  alias Backend.{Accounts, Messages, Modem}
  alias BackendWeb.AccountJSON

  def overview(conn, _params) do
    devices = AccountJSON.all_devices()

    json(conn, %{
      success: true,
      users: Accounts.count_users_by_status(),
      devices: %{total: length(devices), online: Enum.count(devices, & &1.online)},
      messages: %{
        sent_last_24h: Messages.sent_last_24h(:all),
        queued: Messages.queue_depth(:all)
      },
      server_gateway_online: Modem.status() == :ready
    })
  end

  def users(conn, _params) do
    sent = Messages.sent_by_user_last_24h()
    online = for %{user_id: id} <- Backend.Modem.Phone.connected(:all), into: MapSet.new(), do: id

    users =
      for user <- Accounts.list_users() do
        user
        |> AccountJSON.user()
        |> Map.merge(%{
          sent_last_24h: Map.get(sent, user.id, 0),
          custom_daily_limit: user.daily_limit,
          online: MapSet.member?(online, user.id)
        })
      end

    json(conn, %{success: true, users: users})
  end

  def update_user(conn, %{"id" => id} = params) do
    me = conn.assigns.current_user
    attrs = Map.take(params, ["status", "role", "daily_limit"])

    with {id, ""} <- Integer.parse(to_string(id)),
         %{} = user <- Accounts.get_user(id) do
      cond do
        user.id == me.id and (Map.has_key?(attrs, "status") or Map.has_key?(attrs, "role")) ->
          AccountJSON.error(
            conn,
            :unprocessable_entity,
            "invalid_request",
            "You can't change your own role or status."
          )

        true ->
          case Accounts.admin_update_user(user, attrs) do
            {:ok, user} -> json(conn, %{success: true, user: AccountJSON.user(user)})
            {:error, errors} -> AccountJSON.errors_response(conn, errors)
          end
      end
    else
      _ -> AccountJSON.error(conn, :not_found, "not_found", "No such user.")
    end
  end

  def devices(conn, _params), do: json(conn, %{success: true, devices: AccountJSON.all_devices()})
end
