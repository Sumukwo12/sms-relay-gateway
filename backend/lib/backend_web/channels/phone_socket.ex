defmodule BackendWeb.PhoneSocket do
  @moduledoc """
  WebSocket endpoint for the SMS Relay mobile app.

  Mounted at `/phone`.
  Accepts connections providing a binary `token` param and assigns it
  for validation at channel join time.
  """

  use Phoenix.Socket

  channel "gateway:phone", BackendWeb.GatewayChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) when is_binary(token) do
    {:ok, assign(socket, :token, token)}
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(_socket), do: nil
end
