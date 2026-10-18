defmodule BackendWeb.Plugs.PublicApi do
  @moduledoc """
  Gate for the unauthenticated `/api` endpoints used by the demo frontend.
  Disable them with `PUBLIC_API=false` once only integrated systems (via the
  authenticated `/v1` API) should be able to trigger SMS.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    if Application.get_env(:backend, :public_api_enabled, true) do
      conn
    else
      conn
      |> put_status(:not_found)
      |> json(%{success: false, error: "not_found", message: "Use the authenticated /v1 API."})
      |> halt()
    end
  end
end
