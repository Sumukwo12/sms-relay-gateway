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
    - `Backend.Modem.Phone` — sends SMS via an Android phone running our SMS Relay
      app connected over a Phoenix Channel WebSocket (`gateway:phone`). Set
      `MODEM_ADAPTER=phone` and `PHONE_GATEWAY_TOKEN`.
    - `Backend.Modem.Mock` — in-memory modem that logs messages instead of
      sending them. Default in dev and test.

  Adapters implement this module's behaviour and are started under the name
  of the adapter module itself.
  """

  @type status :: :ready | :busy | :disconnected

  @callback start_link(keyword()) :: GenServer.on_start()
  @callback send_sms(phone :: String.t(), message :: String.t()) :: :ok | {:error, term()}
  @callback status() :: status()

  @doc """
  Optional: send with options. `:id` is the outbox message id, which
  adapters that report delivery (the SMS Relay phone) pass to the device so
  its sent/delivered reports can be matched back to the message.
  """
  @callback send_sms(phone :: String.t(), message :: String.t(), opts :: keyword()) ::
              :ok | {:error, term()}
  @optional_callbacks send_sms: 3

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

  @doc "Send an SMS. Returns `:ok` or `{:error, reason}`. See `c:send_sms/3` for `opts`."
  @spec send_sms(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def send_sms(phone, message, opts \\ []) do
    adapter = adapter()

    if opts != [] and function_exported?(adapter, :send_sms, 3),
      do: adapter.send_sms(phone, message, opts),
      else: adapter.send_sms(phone, message)
  end

  @doc "Current modem status — :ready | :busy | :disconnected"
  @spec status() :: status()
  def status, do: adapter().status()

  @doc """
  Status for one user's messages. Only the SMS Relay phone adapter sends per
  user; the single-device adapters answer for everyone.
  """
  @spec status(pos_integer() | nil) :: status()
  def status(nil), do: status()

  def status(user_id) do
    adapter = adapter()

    if Code.ensure_loaded?(adapter) and function_exported?(adapter, :status, 1),
      do: adapter.status(user_id),
      else: adapter.status()
  end

  @doc """
  Whose messages can be sent right now: `:any` for single-device adapters,
  or `%{users: MapSet.t(), system: boolean}` for SMS Relay phones.
  """
  @spec available_owners() :: :any | %{users: MapSet.t(), system: boolean()}
  def available_owners do
    adapter = adapter()

    if Code.ensure_loaded?(adapter) and function_exported?(adapter, :available_owners, 0),
      do: adapter.available_owners(),
      else: :any
  end

  @doc "The configured adapter module."
  @spec adapter() :: module()
  def adapter, do: Application.get_env(:backend, :modem_adapter, Backend.Modem.Mock)
end
