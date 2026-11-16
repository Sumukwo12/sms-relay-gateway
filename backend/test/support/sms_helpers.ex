defmodule Backend.SmsHelpers do
  @moduledoc """
  Test helpers for the SMS flow. The app runs with `Backend.Modem.Mock`
  in test, whose state is global, so tests using this must not be async.
  """

  alias Backend.Modem.Mock

  @doc "Clear rate limits and the mock modem's outbox."
  def reset_sms_state(_context \\ %{}) do
    Cachex.clear(:rate_limit_store)
    Mock.reset()
    :ok
  end

  @doc "Extract the verification code from the last SMS sent to `phone`."
  def sent_code(phone) do
    case Mock.last_message(phone) do
      %{body: body} -> body |> then(&Regex.run(~r/\d{6}/, &1)) |> hd()
      nil -> nil
    end
  end

  @doc "Make a queued message due now (skips its retry backoff)."
  def make_due(id) do
    import Ecto.Query

    Backend.Repo.update_all(
      from(m in Backend.Messages.Message, where: m.id == ^id),
      set: [next_attempt_at: DateTime.add(DateTime.utc_now(), -1, :second)]
    )

    :ok
  end
end
