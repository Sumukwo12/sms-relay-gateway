defmodule Backend.Accounts.User do
  @moduledoc "A person using the gateway: an admin, or a user sending through their own phones."

  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(admin user)
  @statuses ~w(pending approved suspended)

  @timestamps_opts [type: :utc_datetime_usec]

  schema "users" do
    field(:email, :string)
    field(:name, :string)
    field(:password_hash, :string, redact: true)
    field(:role, :string, default: "user")
    field(:status, :string, default: "pending")
    field(:daily_limit, :integer)
    field(:webhook_secret, :string, redact: true)
    field(:webhook_url, :string)
    field(:otp_template, :string)

    timestamps()
  end

  def roles, do: @roles
  def statuses, do: @statuses

  @doc "The tenant every message, code and webhook of this user is stored under."
  def client(%__MODULE__{id: id}), do: client(id)
  def client(id) when is_integer(id), do: "user:#{id}"

  @doc "The user id behind a tenant string, or nil for server-level clients."
  def client_user_id("user:" <> id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  def client_user_id(_), do: nil

  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name])
    |> update_change(:email, &normalize_email/1)
    |> update_change(:name, &String.trim/1)
    |> validate_required([:email], message: "is required")
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, message: "must be a valid email")
    |> validate_length(:email, max: 160)
    |> validate_length(:name, max: 100)
    |> unique_constraint(:email, message: "is already registered")
  end

  def admin_changeset(user, attrs) do
    user
    |> cast(attrs, [:role, :status, :daily_limit])
    |> validate_inclusion(:role, @roles)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:daily_limit, greater_than_or_equal_to: 0, less_than_or_equal_to: 100_000)
  end

  @doc "The user's own integration settings: default webhook URL and OTP text."
  def settings_changeset(user, attrs) do
    attrs =
      Map.new(attrs, fn
        {k, v} when is_binary(v) -> {k, String.trim(v)}
        pair -> pair
      end)

    user
    |> cast(attrs, [:webhook_url, :otp_template], empty_values: [nil, ""])
    |> validate_length(:webhook_url, max: 500)
    |> validate_format(:webhook_url, ~r{^https?://[^\s/]+}, message: "must be an http(s) URL")
    |> validate_length(:otp_template, max: 300)
    |> validate_format(:otp_template, ~r/\{code\}/, message: "must contain {code}")
  end

  def normalize_email(email) when is_binary(email),
    do: email |> String.trim() |> String.downcase()

  def normalize_email(email), do: email
end

defmodule Backend.Accounts.Session do
  @moduledoc false
  use Ecto.Schema

  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "user_sessions" do
    belongs_to(:user, Backend.Accounts.User)
    field(:token_hash, :string, redact: true)
    field(:expires_at, :utc_datetime_usec)
    timestamps()
  end
end

defmodule Backend.Accounts.Device do
  @moduledoc "A phone running the SMS Relay app, signed in to a user's account."
  use Ecto.Schema

  @timestamps_opts [type: :utc_datetime_usec]

  schema "devices" do
    belongs_to(:user, Backend.Accounts.User)
    field(:name, :string)
    field(:model, :string)
    field(:token_hash, :string, redact: true)
    field(:app_version, :string)
    field(:last_seen_at, :utc_datetime_usec)
    field(:revoked_at, :utc_datetime_usec)
    timestamps()
  end
end

defmodule Backend.Accounts.ApiKey do
  @moduledoc "A user's key for the /v1 API. Only a hash is stored."
  use Ecto.Schema

  @timestamps_opts [type: :utc_datetime_usec]

  schema "api_keys" do
    belongs_to(:user, Backend.Accounts.User)
    field(:name, :string)
    field(:prefix, :string)
    field(:key_hash, :string, redact: true)
    # "live" sends SMS; "test" (sk_test_…) only simulates them
    field(:mode, :string, default: "live")
    field(:last_used_at, :utc_datetime_usec)
    field(:revoked_at, :utc_datetime_usec)
    timestamps()
  end
end
