defmodule Backend.Modem.Mock do
  @moduledoc """
  In-memory modem for development and tests.

  Messages are logged (so you can read the verification code in the server
  console) and kept in an outbox instead of being sent over the air.

  Tests can simulate hardware problems with `set_status/1`:

      Backend.Modem.Mock.set_status(:disconnected)
      Backend.Modem.Mock.set_status({:failing, {:cms_error, "500"}})
  """

  use Agent
  require Logger

  @behaviour Backend.Modem

  @outbox_limit 100

  @impl Backend.Modem
  def start_link(_opts) do
    Agent.start_link(fn -> initial_state() end, name: __MODULE__)
  end

  @impl Backend.Modem
  def send_sms(phone, message) do
    Agent.get_and_update(__MODULE__, fn
      %{status: :ready} = state ->
        Logger.info("[Modem.Mock] SMS to #{phone}: #{message}")
        entry = %{to: phone, body: message, sent_at: DateTime.utc_now()}
        {:ok, %{state | outbox: [entry | Enum.take(state.outbox, @outbox_limit - 1)]}}

      %{status: :disconnected} = state ->
        {{:error, :modem_disconnected}, state}

      %{status: {:failing, reason}} = state ->
        {{:error, reason}, state}
    end)
  end

  @impl Backend.Modem
  def status do
    case Agent.get(__MODULE__, & &1.status) do
      {:failing, _} -> :ready
      status -> status
    end
  end

  @doc "Force a status: `:ready`, `:disconnected` or `{:failing, reason}`."
  def set_status(status), do: Agent.update(__MODULE__, &%{&1 | status: status})

  @doc "Messages sent so far, newest first."
  def outbox, do: Agent.get(__MODULE__, & &1.outbox)

  @doc "The newest message sent to `phone`, or nil."
  def last_message(phone), do: Enum.find(outbox(), &(&1.to == phone))

  @doc "Clear the outbox and return to `:ready`."
  def reset, do: Agent.update(__MODULE__, fn _ -> initial_state() end)

  defp initial_state, do: %{status: :ready, outbox: []}
end
