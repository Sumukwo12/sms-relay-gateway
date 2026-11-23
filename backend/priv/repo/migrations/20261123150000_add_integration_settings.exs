defmodule Backend.Repo.Migrations.AddIntegrationSettings do
  use Ecto.Migration

  def change do
    # "live" keys send SMS; "test" keys (sk_test_…) only simulate them
    alter table(:api_keys) do
      add :mode, :string, null: false, default: "live"
    end

    # Simulated by a test key: never sent, never counted against limits
    alter table(:messages) do
      add :test, :boolean, null: false, default: false
    end

    alter table(:users) do
      # Default destination for message and phone webhooks
      add :webhook_url, :string
      # Default OTP text, with {code} (and optionally {minutes})
      add :otp_template, :string
    end
  end
end
