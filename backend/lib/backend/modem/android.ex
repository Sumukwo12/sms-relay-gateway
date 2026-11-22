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

  alias Backend.PhoneUtils

  @behaviour Backend.Modem

  # Health check interval (ms)
  @health_interval 15_000
  # Health check timeout (ms)
  @health_timeout 2_000

  # ── Public API ──────────────────────────────────────────────────────────────

  @impl Backend.Modem
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl Backend.Modem
  def send_sms(phone, message) do
    GenServer.call(__MODULE__, {:send_sms, phone, message}, 30_000)
  end

  @impl Backend.Modem
  def status do
    :persistent_term.get({__MODULE__, :status}, :disconnected)
  end

  # ── GenServer callbacks ─────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    state = %{
      base_url: config(:android_sms_url, "http://192.168.1.5:8080"),
      username: config(:android_sms_user, ""),
      password: config(:android_sms_pass, ""),
      status: :disconnected
    }

    set_status(:disconnected)
    # Perform immediate initial health check
    send(self(), :check_health)
    Logger.info("[Modem.Android] Adapter started → #{state.base_url}")
    {:ok, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, :persistent_term.get({__MODULE__, :status}, state.status), state}
  end

  @impl true
  def handle_call({:send_sms, phone, message}, _from, state) do
    masked_phone = PhoneUtils.mask(phone)
    set_status(:busy)

    url = "#{state.base_url}/message"

    body = %{
      "message" => message,
      "phoneNumbers" => [phone]
    }

    Logger.debug("[Modem.Android] POST #{url} to=#{masked_phone}")

    result =
      case Req.post(url,
             auth: {:basic, "#{state.username}:#{state.password}"},
             json: body,
             retry: false,
             receive_timeout: 25_000
           ) do
        {:ok, %{status: status}} when status in 200..299 ->
          Logger.info("[Modem.Android] SMS accepted for #{masked_phone}")
          set_status(:ready)
          :ok

        {:ok, %{status: status, body: resp_body}} ->
          Logger.error("[Modem.Android] Gateway rejected (#{status}): #{inspect(resp_body)}")
          set_status(state.status)
          {:error, {:http_error, status}}

        {:error, reason} ->
          Logger.error("[Modem.Android] Request failed: #{inspect(reason)}")
          set_status(:disconnected)
          {:error, :modem_disconnected}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_info(:check_health, state) do
    new_status =
      case Req.get("#{state.base_url}/health",
             auth: {:basic, "#{state.username}:#{state.password}"},
             retry: false,
             receive_timeout: @health_timeout
           ) do
        {:ok, %{status: s}} when s in 200..299 -> :ready
        _ -> :disconnected
      end

    # Only update persistent_term if a send is not actively marking it busy
    if :persistent_term.get({__MODULE__, :status}, :disconnected) != :busy do
      set_status(new_status)
    end

    Process.send_after(self(), :check_health, @health_interval)
    {:noreply, %{state | status: new_status}}
  end

  @impl true
  def terminate(_reason, _state) do
    set_status(:disconnected)
    :ok
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp set_status(status) do
    :persistent_term.put({__MODULE__, :status}, status)
    status
  end

  defp config(key, default), do: Application.get_env(:backend, key, default)
end
