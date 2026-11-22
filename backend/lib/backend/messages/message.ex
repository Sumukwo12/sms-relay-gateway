defmodule Backend.Messages.Message do
  @moduledoc """
  One outgoing SMS in the outbox.

  Status lifecycle:

      queued ──► sending ──► sent ──► delivered
         ▲          │
         └──retry───┤
                    └──► failed   (attempts exhausted, expired, or rejected)
  """

  use Ecto.Schema

  @statuses ~w(queued sending sent delivered failed)
  @kinds ~w(otp notification)

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "messages" do
    field(:client, :string)
    field(:kind, :string)
    field(:to, :string)
    field(:body, :string)
    field(:segments, :integer, default: 1)
    field(:status, :string, default: "queued")
    field(:attempts, :integer, default: 0)
    field(:max_attempts, :integer)
    field(:last_error, :string)
    field(:reference, :string)
    field(:callback_url, :string)
    field(:idempotency_key, :string)
    field(:next_attempt_at, :utc_datetime_usec)
    field(:expires_at, :utc_datetime_usec)
    field(:sent_at, :utc_datetime_usec)
    field(:delivered_at, :utc_datetime_usec)
    field(:failed_at, :utc_datetime_usec)

    timestamps()
  end

  def statuses, do: @statuses
  def kinds, do: @kinds

  @doc "Statuses after which the outbox never touches the message again."
  def final?(%__MODULE__{status: status}), do: status in ~w(delivered failed)
end
