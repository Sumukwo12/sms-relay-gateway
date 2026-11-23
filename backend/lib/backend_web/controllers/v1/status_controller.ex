defmodule BackendWeb.V1.StatusController do
  @moduledoc """
  GET /v1/status — gateway health for monitoring. With a user key it
  describes that user's phones, queue and daily limit; with a server key,
  the server-level route.
  """

  use BackendWeb, :controller

  alias Backend.{Accounts, Messages, Modem, Monitor, Outbox, Webhooks}

  def show(conn, _params) do
    case conn.assigns[:api_user] do
      nil -> json(conn, system_status())
      user -> json(conn, user_status(user))
    end
  end

  defp system_status do
    status = Modem.status()

    %{
      success: true,
      modem: %{status: status, ready: status == :ready, device: device_info()},
      queue: %{
        pending: Messages.queue_depth(),
        # Both in SMS parts: a long message counts once per part
        sent_last_24h: Messages.sent_last_24h(),
        daily_limit: Outbox.daily_limit()
      },
      webhooks: %{pending: Webhooks.pending_count()},
      alerts:
        for({alert, message} <- Monitor.active_alerts(), do: %{alert: alert, message: message})
    }
  end

  defp user_status(user) do
    status = Modem.status(user.id)

    %{
      success: true,
      account: %{status: user.status},
      modem: %{status: status, ready: status == :ready},
      devices: BackendWeb.AccountJSON.devices(user.id),
      queue: %{
        pending: Messages.queue_depth(user.id),
        sent_last_24h: Messages.sent_last_24h(user.id),
        daily_limit: Accounts.daily_limit(user)
      }
    }
  end

  defp device_info do
    if Modem.adapter() == Backend.Modem.Phone, do: Backend.Modem.Phone.get_device_info()
  end
end
