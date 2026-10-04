defmodule Backend.Modem.Android do
  @moduledoc """
  Modem adapter that sends SMS via an Android phone running the
  Android SMS Gateway app (https://sms-gate.app/).

  The app exposes a local REST API on your phone's Wi-Fi IP address.
  Both this server and the Android phone must be on the same network.

  ## Setup

  1. Install "Android SMS Gateway" on your Android phone (free, open source).
     https://play.google.com/store/apps/details?id=me.capcom.smsgateway

  2. Open the app. Note the **Local API URL**, **username**, and **password**
     shown on the main screen (e.g. http://192.168.1.5:8080).

  3. Set these three environment variables before starting the backend:

         MODEM_ADAPTER=android
         ANDROID_SMS_URL=http://192.168.1.5:8080
         ANDROID_SMS_USER=<username from app>
         ANDROID_SMS_PASS=<password from app>

  ## API used

  POST /message
  Body: { "message": "...", "phoneNumbers": ["+254712345678"] }
  Auth: HTTP Basic
  """

  use GenServer
  require Logger

  @behaviour Backend.Modem

  # ── Public API ──────────────────────────────────────────────────────────────

  @impl Backend.Modem
  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl Backend.Modem
  def send_sms(phone, message) do
    GenServer.call(__MODULE__, {:send_sms, phone, message}, 30_000)
  end

  @impl Backend.Modem
  def status, do: GenServer.call(__MODULE__, :status)

  # ── GenServer callbacks ─────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    state = %{
      base_url: config(:android_sms_url, "http://192.168.1.5:8080"),
      username: config(:android_sms_user, ""),
      password: config(:android_sms_pass, "")
    }

    Logger.info("[Modem.Android] Adapter started → #{state.base_url}")
    {:ok, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    # Do a lightweight health-check against the gateway app
    status =
      case Req.get("#{state.base_url}/health",
             auth: {state.username, state.password},
             receive_timeout: 5_000
           ) do
        {:ok, %{status: s}} when s in 200..299 -> :ready
        _ -> :disconnected
      end

    {:reply, status, state}
  end

  @impl true
  def handle_call({:send_sms, phone, message}, _from, state) do
    url = "#{state.base_url}/message"

    body = %{
      "message" => message,
      "phoneNumbers" => [phone]
    }

    Logger.debug("[Modem.Android] POST #{url} to=#{phone}")

    result =
      case Req.post(url,
             auth: {state.username, state.password},
             json: body,
             receive_timeout: 25_000
           ) do
        {:ok, %{status: status}} when status in 200..299 ->
          Logger.info("[Modem.Android] SMS accepted for #{phone}")
          :ok

        {:ok, %{status: status, body: body}} ->
          Logger.error("[Modem.Android] Gateway rejected (#{status}): #{inspect(body)}")
          {:error, {:http_error, status}}

        {:error, reason} ->
          Logger.error("[Modem.Android] Request failed: #{inspect(reason)}")
          {:error, :modem_disconnected}
      end

    {:reply, result, state}
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp config(key, default), do: Application.get_env(:backend, key, default)
end
