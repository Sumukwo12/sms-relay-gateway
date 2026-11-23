defmodule Backend.Repo.Migrations.AddAccounts do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :email, :string, null: false
      add :name, :string
      add :password_hash, :string, null: false
      # "admin" | "user"
      add :role, :string, null: false, default: "user"
      # "pending" | "approved" | "suspended"
      add :status, :string, null: false, default: "pending"
      # SMS parts per rolling 24h; NULL uses the server default
      add :daily_limit, :integer
      # Signs this user's webhooks (X-Signature); their API keys are stored hashed
      add :webhook_secret, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:email])

    create table(:user_sessions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token_hash, :string, null: false
      add :expires_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:user_sessions, [:token_hash])
    create index(:user_sessions, [:user_id])

    # A phone running the SMS Relay app, signed in to a user's account
    create table(:devices) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :model, :string
      add :token_hash, :string, null: false
      add :app_version, :string
      add :last_seen_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:devices, [:token_hash])
    create index(:devices, [:user_id])

    create table(:api_keys) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      # First characters of the key, so users can tell their keys apart
      add :prefix, :string, null: false
      add :key_hash, :string, null: false
      add :last_used_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:api_keys, [:key_hash])
    create index(:api_keys, [:user_id])

    # NULL user_id: sent for the server itself (public demo page, API_KEYS
    # from the environment), through the PHONE_GATEWAY_TOKEN phone or an
    # admin's phone.
    alter table(:messages) do
      add :user_id, :integer
      # The phone the sender asked for, if any
      add :device_id, :integer
      add :api_key_id, :integer
    end

    create index(:messages, [:user_id, :inserted_at])
    create index(:messages, [:user_id, :sent_at])
  end
end
