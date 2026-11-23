defmodule Backend.Accounts do
  @moduledoc """
  User accounts, their sessions, the phones they link and their API keys.

  Registering always creates a `pending` user: they can sign in, link a phone
  and create keys, but nothing they queue is sent until an admin approves
  them. Nobody can register as an admin. The admin account comes from the
  server's `ADMIN_EMAIL` / `ADMIN_PASSWORD` (`ensure_admin/0`, at boot), and
  admins can promote other users. `suspended` users cannot sign in, their
  keys stop working and their phones are disconnected.
  """

  import Ecto.Query
  require Logger

  alias Backend.Accounts.{ApiKey, Device, Password, Session, Token, User}
  alias Backend.Repo

  @session_ttl_days 30
  @min_password 8
  @max_password 200
  # Don't write last_used_at/last_seen_at more often than this
  @touch_interval_seconds 60

  # ── Users ───────────────────────────────────────────────────────────────────

  @doc "Create an account. Returns `{:ok, user}` or `{:error, %{field => message}}`."
  def register(attrs) do
    password = attr(attrs, :password)
    changeset = User.registration_changeset(%User{}, stringify(attrs))

    with :ok <- validate_password(password),
         true <- changeset.valid? || {:error, errors(changeset)} do
      changeset
      |> Ecto.Changeset.change(
        password_hash: Password.hash(password),
        role: "user",
        status: "pending",
        webhook_secret: Token.generate("whsec_", 24)
      )
      |> Repo.insert()
      |> case do
        {:ok, user} ->
          Logger.info("[Accounts] Registered user #{user.id} (#{user.role}, #{user.status})")
          {:ok, user}

        {:error, changeset} ->
          {:error, errors(changeset)}
      end
    end
  end

  @doc """
  Make sure the server's admin account exists: `config :backend, admin:
  {email, password}` (`ADMIN_EMAIL` / `ADMIN_PASSWORD`). Creates it, or turns
  an existing account with that email into an approved admin (its password
  is left alone). Does nothing when not configured.
  """
  def ensure_admin do
    case Application.get_env(:backend, :admin) do
      {email, password} when is_binary(email) and is_binary(password) ->
        email = User.normalize_email(email)

        case Repo.get_by(User, email: email) do
          nil ->
            case register(%{email: email, password: password, name: "Admin"}) do
              {:ok, user} ->
                promote_admin(user)

              {:error, errors} ->
                Logger.error(
                  "[Accounts] Could not create the admin from ADMIN_EMAIL/ADMIN_PASSWORD: " <>
                    Enum.map_join(errors, "; ", fn {field, msg} -> "#{field} #{msg}" end)
                )

                {:error, errors}
            end

          %User{role: "admin", status: "approved"} = user ->
            {:ok, user}

          user ->
            promote_admin(user)
        end

      _ ->
        :not_configured
    end
  end

  defp promote_admin(user) do
    user = user |> Ecto.Changeset.change(role: "admin", status: "approved") |> Repo.update!()
    Logger.info("[Accounts] #{user.email} is the server admin")
    {:ok, user}
  end

  @doc "Check an email and password."
  def authenticate(email, password) when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: User.normalize_email(email))

    cond do
      is_nil(user) -> no_user()
      not Password.verify(password, user.password_hash) -> {:error, :invalid_credentials}
      user.status == "suspended" -> {:error, :suspended}
      true -> {:ok, user}
    end
  end

  def authenticate(_email, _password), do: {:error, :invalid_credentials}

  defp no_user do
    Password.no_user_verify()
    {:error, :invalid_credentials}
  end

  def get_user(id), do: Repo.get(User, id)

  def change_password(%User{} = user, current, new) do
    cond do
      not Password.verify(current || "", user.password_hash) ->
        {:error, %{current_password: "is incorrect"}}

      (error = validate_password(new)) != :ok ->
        error

      true ->
        user |> Ecto.Changeset.change(password_hash: Password.hash(new)) |> Repo.update!()
        # Sign out every other browser
        Repo.delete_all(from(s in Session, where: s.user_id == ^user.id))
        :ok
    end
  end

  def rotate_webhook_secret(%User{} = user) do
    user |> Ecto.Changeset.change(webhook_secret: Token.generate("whsec_", 24)) |> Repo.update!()
  end

  @doc "The secret that signs webhooks for a tenant (`user:<id>`), if it is a user."
  def webhook_secret_for_client(client) do
    with id when is_integer(id) <- User.client_user_id(client),
         %User{webhook_secret: secret} <- Repo.get(User, id) do
      secret
    else
      _ -> nil
    end
  end

  def can_send?(%User{status: "approved"}), do: true
  def can_send?(_), do: false

  @doc "SMS parts the user may send per rolling 24 hours."
  def daily_limit(%User{daily_limit: limit}) when is_integer(limit), do: limit
  def daily_limit(_user), do: Application.get_env(:backend, :user_daily_send_limit, 200)

  @doc "Users whose queued messages must not be sent: not approved, or over their daily limit."
  def blocked_user_ids(sent_by_user) do
    not_approved = Repo.all(from(u in User, where: u.status != "approved", select: u.id))

    over_limit =
      case Map.keys(sent_by_user) do
        [] ->
          []

        ids ->
          from(u in User, where: u.id in ^ids)
          |> Repo.all()
          |> Enum.filter(&(Map.get(sent_by_user, &1.id, 0) >= daily_limit(&1)))
          |> Enum.map(& &1.id)
      end

    Enum.uniq(not_approved ++ over_limit)
  end

  # ── Admin ───────────────────────────────────────────────────────────────────

  def list_users, do: Repo.all(from(u in User, order_by: [desc: u.inserted_at]))

  def count_users_by_status do
    from(u in User, group_by: u.status, select: {u.status, count(u.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Change a user's role, status or daily limit (admin only)."
  def admin_update_user(%User{} = user, attrs) do
    changeset = User.admin_changeset(user, stringify(attrs))

    case Repo.update(changeset) do
      {:ok, updated} ->
        if updated.status == "suspended" and user.status != "suspended" do
          Repo.delete_all(from(s in Session, where: s.user_id == ^user.id))
          Backend.Modem.Phone.disconnect_user(user.id)
        end

        Logger.info("[Accounts] Admin updated user #{user.id}: #{inspect(changeset.changes)}")
        {:ok, updated}

      {:error, changeset} ->
        {:error, errors(changeset)}
    end
  end

  # ── Sessions (web dashboard) ────────────────────────────────────────────────

  def create_session(%User{} = user) do
    token = Token.generate("ses_")
    expires_at = DateTime.add(now(), @session_ttl_days * 86_400, :second)

    Repo.insert!(%Session{
      user_id: user.id,
      token_hash: Token.hash(token),
      expires_at: expires_at
    })

    token
  end

  def session_ttl_seconds, do: @session_ttl_days * 86_400

  def get_user_by_session(token) when is_binary(token) do
    now = now()

    Repo.one(
      from(s in Session,
        join: u in assoc(s, :user),
        where: s.token_hash == ^Token.hash(token) and s.expires_at > ^now,
        where: u.status != "suspended",
        select: u
      )
    )
  end

  def get_user_by_session(_), do: nil

  def delete_session(token) when is_binary(token) do
    Repo.delete_all(from(s in Session, where: s.token_hash == ^Token.hash(token)))
    :ok
  end

  def delete_session(_), do: :ok

  def purge_expired_sessions do
    now = now()
    {count, _} = Repo.delete_all(from(s in Session, where: s.expires_at <= ^now))
    count
  end

  # ── Devices (phones running the SMS Relay app) ──────────────────────────────

  @doc "Link a phone to the user. Returns `{:ok, device, token}`; the token is shown once."
  def create_device(%User{} = user, attrs \\ %{}) do
    token = Token.generate("dev_")

    device =
      Repo.insert!(%Device{
        user_id: user.id,
        name: attr(attrs, :name) |> clean_name("Android phone"),
        model: attr(attrs, :model) |> clean_name(nil),
        app_version: attr(attrs, :app_version) |> clean_name(nil),
        token_hash: Token.hash(token),
        last_seen_at: now()
      })

    Logger.info("[Accounts] User #{user.id} linked device #{device.id}")
    {:ok, %{device | user: user}, token}
  end

  @doc "The active device for a token, with its user preloaded."
  def authenticate_device(token) when is_binary(token) do
    query =
      from(d in Device,
        join: u in assoc(d, :user),
        where: d.token_hash == ^Token.hash(token) and is_nil(d.revoked_at),
        where: u.status != "suspended",
        preload: [user: u]
      )

    case Repo.one(query) do
      nil -> :error
      device -> {:ok, device}
    end
  end

  def authenticate_device(_), do: :error

  def list_devices(user_id) do
    Repo.all(
      from(d in Device,
        where: d.user_id == ^user_id and is_nil(d.revoked_at),
        order_by: [desc: d.inserted_at]
      )
    )
  end

  def list_all_devices do
    Repo.all(
      from(d in Device,
        where: is_nil(d.revoked_at),
        order_by: [desc: d.last_seen_at],
        preload: :user
      )
    )
  end

  def get_device(user_id, id) do
    with {id, ""} <- Integer.parse(to_string(id)) do
      Repo.one(
        from(d in Device, where: d.id == ^id and d.user_id == ^user_id and is_nil(d.revoked_at))
      )
    else
      _ -> nil
    end
  end

  def rename_device(%Device{} = device, name) do
    case clean_name(name, nil) do
      nil -> {:error, %{name: "is required"}}
      name -> {:ok, device |> Ecto.Changeset.change(name: name) |> Repo.update!()}
    end
  end

  @doc "Sign a phone out: its token stops working and it is disconnected now."
  def revoke_device(%Device{} = device) do
    device = device |> Ecto.Changeset.change(revoked_at: now()) |> Repo.update!()
    Backend.Modem.Phone.disconnect_device(device.id)
    {:ok, device}
  end

  @doc "Record that a phone was seen (connected or sent telemetry)."
  def touch_device(device_id, app_version \\ nil) do
    cutoff = DateTime.add(now(), -@touch_interval_seconds, :second)
    changes = [last_seen_at: now(), updated_at: now()]

    changes =
      if is_binary(app_version), do: [{:app_version, app_version} | changes], else: changes

    query = from(d in Device, where: d.id == ^device_id)

    # A new app version is always recorded; plain heartbeats are throttled
    query =
      if is_binary(app_version),
        do: query,
        else: where(query, [d], is_nil(d.last_seen_at) or d.last_seen_at < ^cutoff)

    Repo.update_all(query, set: changes)

    :ok
  end

  # ── API keys ────────────────────────────────────────────────────────────────

  @doc "Create an API key. Returns `{:ok, api_key, key}`; the key is shown once."
  def create_api_key(%User{} = user, name) do
    case clean_name(name, nil) do
      nil ->
        {:error, %{name: "is required"}}

      name ->
        key = Token.generate("sk_")

        api_key =
          Repo.insert!(%ApiKey{
            user_id: user.id,
            name: name,
            prefix: String.slice(key, 0, 10),
            key_hash: Token.hash(key)
          })

        {:ok, api_key, key}
    end
  end

  def list_api_keys(user_id) do
    Repo.all(
      from(k in ApiKey,
        where: k.user_id == ^user_id and is_nil(k.revoked_at),
        order_by: [desc: k.inserted_at]
      )
    )
  end

  def revoke_api_key(user_id, id) do
    with {id, ""} <- Integer.parse(to_string(id)),
         {1, _} <-
           from(k in ApiKey,
             where: k.id == ^id and k.user_id == ^user_id and is_nil(k.revoked_at)
           )
           |> Repo.update_all(set: [revoked_at: now(), updated_at: now()]) do
      :ok
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "The active key (with its user) for a presented key."
  def authenticate_api_key(key) when is_binary(key) do
    query =
      from(k in ApiKey,
        join: u in assoc(k, :user),
        where: k.key_hash == ^Token.hash(key) and is_nil(k.revoked_at),
        preload: [user: u]
      )

    case Repo.one(query) do
      nil ->
        :error

      api_key ->
        touch_api_key(api_key)
        {:ok, api_key}
    end
  end

  def authenticate_api_key(_), do: :error

  defp touch_api_key(%ApiKey{last_used_at: last} = api_key) do
    if is_nil(last) or DateTime.diff(now(), last) >= @touch_interval_seconds do
      from(k in ApiKey, where: k.id == ^api_key.id)
      |> Repo.update_all(set: [last_used_at: now()])
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp validate_password(password) when is_binary(password) do
    cond do
      String.length(password) < @min_password ->
        {:error, %{password: "must be at least #{@min_password} characters"}}

      byte_size(password) > @max_password ->
        {:error, %{password: "must be at most #{@max_password} characters"}}

      true ->
        :ok
    end
  end

  defp validate_password(_), do: {:error, %{password: "is required"}}

  @doc "First error message per field, e.g. `%{email: \"is already registered\"}`."
  def errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
      end)
    end)
    |> Map.new(fn {field, [message | _]} -> {field, message} end)
  end

  defp clean_name(value, default) when is_binary(value) do
    case value |> String.trim() |> String.slice(0, 80) do
      "" -> default
      name -> name
    end
  end

  defp clean_name(_value, default), do: default

  defp attr(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

  defp stringify(attrs), do: Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

  defp now, do: DateTime.utc_now()
end
