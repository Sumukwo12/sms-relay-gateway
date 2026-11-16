defmodule BackendWeb.V1.StatusController do
  @moduledoc "GET /v1/status — gateway health for monitoring."

  use BackendWeb, :controller

  alias Backend.{Messages, Modem, Monitor, Outbox, Webhooks}

  def show(conn, _params) do
    status = Modem.status()

    json(conn, %{
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
    })
  end

  defp device_info do
    if Modem.adapter() == Backend.Modem.Phone, do: Backend.Modem.Phone.get_device_info()
  end
end
