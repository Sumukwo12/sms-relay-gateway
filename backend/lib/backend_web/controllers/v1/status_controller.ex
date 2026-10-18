defmodule BackendWeb.V1.StatusController do
  @moduledoc "GET /v1/status — gateway health for monitoring."

  use BackendWeb, :controller

  alias Backend.{Messages, Modem, Outbox}

  def show(conn, _params) do
    status = Modem.status()

    json(conn, %{
      success: true,
      modem: %{status: status, ready: status == :ready, device: device_info()},
      queue: %{
        pending: Messages.queue_depth(),
        sent_last_24h: Messages.sent_last_24h(),
        daily_limit: Outbox.daily_limit()
      }
    })
  end

  defp device_info do
    if Modem.adapter() == Backend.Modem.Phone, do: Backend.Modem.Phone.get_device_info()
  end
end
