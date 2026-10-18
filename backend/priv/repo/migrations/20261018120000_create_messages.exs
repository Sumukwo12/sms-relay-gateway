defmodule Backend.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages, primary_key: false) do
      add :id, :string, primary_key: true
      add :client, :string, null: false
      add :kind, :string, null: false
      add :to, :string, null: false
      add :body, :text, null: false
      add :status, :string, null: false
      add :attempts, :integer, null: false, default: 0
      add :max_attempts, :integer, null: false
      add :last_error, :string
      add :reference, :string
      add :callback_url, :string
      add :next_attempt_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :sent_at, :utc_datetime_usec
      add :delivered_at, :utc_datetime_usec
      add :failed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:messages, [:status, :next_attempt_at])
    create index(:messages, [:client, :inserted_at])
    create index(:messages, [:sent_at])
  end
end
