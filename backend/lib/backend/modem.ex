defmodule Backend.Modem do
  @moduledoc """
  Facade over the SMS transport.

  The actual transport is chosen with the `:modem_adapter` config key:

    - `Backend.Modem.UART` — real USB GSM modem over a serial port (AT commands).
      Requires the optional `:circuits_uart` dependency, which is only fetched
      and compiled when `MODEM_ADAPTER=uart` (or in `:prod`), because it needs
      a C toolchain (`make` + `gcc`).
    - `Backend.Modem.Android` — sends SMS via an Android phone running the
      Android SMS Gateway app (https://sms-gate.app/) over local Wi-Fi.
      Set `MODEM_ADAPTER=android` plus `ANDROID_SMS_URL`, `ANDROID_SMS_USER`,
      and `ANDROID_SMS_PASS` environment variables.
    - `Backend.Modem.Mock` — in-memory modem that logs messages instead of
      sending them. Default in dev and test.

  Adapters implement this module's behaviour and are started under the name
  of the adapter module itself.
  """

  @type status :: :ready | :busy | :disconnected

  @callback start_link(keyword()) :: GenServer.on_start()
  @callback send_sms(phone :: String.t(), message :: String.t()) :: :ok | {:error, term()}
  @callback status() :: status()

  def child_spec(opts) do
    adapter = adapter()

    unless Code.ensure_loaded?(adapter) do
      raise """
      modem adapter #{inspect(adapter)} is not available.

      Backend.Modem.UART needs the :circuits_uart dependency. Fetch and compile
      it with MODEM_ADAPTER=uart set (requires make + gcc), e.g.:

          MODEM_ADAPTER=uart mix deps.get && MODEM_ADAPTER=uart mix phx.server
      """
    end

    %{id: __MODULE__, start: {adapter, :start_link, [opts]}}
  end

  @doc "Send an SMS. Returns `:ok` or `{:error, reason}`."
  @spec send_sms(String.t(), String.t()) :: :ok | {:error, term()}
  def send_sms(phone, message), do: adapter().send_sms(phone, message)

  @doc "Current modem status — :ready | :busy | :disconnected"
  @spec status() :: status()
  def status, do: adapter().status()

  @doc "The configured adapter module."
  @spec adapter() :: module()
  def adapter, do: Application.get_env(:backend, :modem_adapter, Backend.Modem.Mock)
end
