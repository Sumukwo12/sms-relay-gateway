defmodule Backend.Repo.Migrations.AddOtpCodesWebhooksAndSegments do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      # SMS parts the body needs; the daily cap counts parts, not messages
      add :segments, :integer, null: false, default: 1
      add :idempotency_key, :string
    end

    # NULL keys never collide in SQLite, so only keyed requests are deduplicated
    create unique_index(:messages, [:client, :idempotency_key])

    # Active verification codes, so a restart doesn't strand queued OTP SMS
    create table(:otp_codes) do
      add :client, :string, null: false
      add :phone, :string, null: false
      add :code_hash, :string, null: false
      add :attempts, :integer, null: false, default: 0
      add :expires_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:otp_codes, [:client, :phone])
    create index(:otp_codes, [:expires_at])

    # Webhook deliveries, retried until the receiver accepts them
    create table(:webhook_deliveries) do
      add :message_id, :string, null: false
      add :client, :string, null: false
      add :url, :string, null: false
      add :event, :string, null: false
      add :payload, :text, null: false
      add :status, :string, null: false
      add :attempts, :integer, null: false, default: 0
      add :last_error, :string
      add :next_attempt_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:webhook_deliveries, [:status, :next_attempt_at])
    create index(:webhook_deliveries, [:message_id])
  end
end
