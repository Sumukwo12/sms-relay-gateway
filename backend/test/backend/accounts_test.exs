defmodule Backend.AccountsTest do
  use Backend.DataCase, async: false

  import Backend.AccountHelpers

  alias Backend.Accounts
  alias Backend.Accounts.User

  describe "register/1" do
    test "always creates a pending user, even for the very first account" do
      {:ok, first} = Accounts.register(%{email: "Owner@Example.com ", password: password()})
      assert %User{email: "owner@example.com", role: "user", status: "pending"} = first
      assert "whsec_" <> _ = first.webhook_secret

      {:ok, second} = Accounts.register(%{"email" => "dev@example.com", "password" => password()})
      assert %User{role: "user", status: "pending"} = second
    end
  end

  describe "ensure_admin/0" do
    setup do
      on_exit(fn -> Application.put_env(:backend, :admin, nil) end)
    end

    test "creates the configured admin" do
      assert :not_configured = Accounts.ensure_admin()

      Application.put_env(:backend, :admin, {"Boss@Example.com", password()})

      assert {:ok, %User{email: "boss@example.com", role: "admin", status: "approved"}} =
               Accounts.ensure_admin()

      assert {:ok, %User{role: "admin"}} = Accounts.authenticate("boss@example.com", password())
      # Running again (every boot) changes nothing
      assert {:ok, %User{role: "admin"}} = Accounts.ensure_admin()
    end

    test "promotes an existing account without changing its password" do
      {:ok, _} = Accounts.register(%{email: "boss@example.com", password: "their own password"})
      Application.put_env(:backend, :admin, {"boss@example.com", "configured password"})

      assert {:ok, %User{role: "admin", status: "approved"}} = Accounts.ensure_admin()
      assert {:ok, _} = Accounts.authenticate("boss@example.com", "their own password")
    end
  end

  describe "register/1 validation" do
    test "validates email, password and uniqueness" do
      assert {:error, %{password: "must be at least 8 characters"}} =
               Accounts.register(%{email: "a@example.com", password: "short"})

      assert {:error, %{email: "must be a valid email"}} =
               Accounts.register(%{email: "nope", password: password()})

      {:ok, _} = Accounts.register(%{email: "a@example.com", password: password()})

      assert {:error, %{email: "is already registered"}} =
               Accounts.register(%{email: "A@example.com", password: password()})
    end
  end

  describe "authenticate/2" do
    test "checks the password and refuses suspended accounts" do
      user = user_fixture(email: "me@example.com")

      assert {:ok, %User{id: id}} = Accounts.authenticate("ME@example.com", password())
      assert id == user.id

      assert {:error, :invalid_credentials} =
               Accounts.authenticate("me@example.com", "wrong pass")

      assert {:error, :invalid_credentials} = Accounts.authenticate("who@example.com", password())

      {:ok, _} = Accounts.admin_update_user(user, %{status: "suspended"})
      assert {:error, :suspended} = Accounts.authenticate("me@example.com", password())
    end
  end

  test "sessions sign in until deleted, and stop when the user is suspended" do
    user = user_fixture()
    token = Accounts.create_session(user)

    assert %User{id: id} = Accounts.get_user_by_session(token)
    assert id == user.id
    assert Accounts.get_user_by_session("ses_nope") == nil

    Accounts.delete_session(token)
    assert Accounts.get_user_by_session(token) == nil

    token = Accounts.create_session(user)
    {:ok, _} = Accounts.admin_update_user(user, %{status: "suspended"})
    assert Accounts.get_user_by_session(token) == nil
  end

  test "changing the password needs the current one and signs out other sessions" do
    user = user_fixture()
    token = Accounts.create_session(user)

    assert {:error, %{current_password: _}} =
             Accounts.change_password(user, "wrong", "new password!")

    assert :ok = Accounts.change_password(user, password(), "new password!")
    assert Accounts.get_user_by_session(token) == nil
    assert {:ok, _} = Accounts.authenticate(user.email, "new password!")
  end

  describe "API keys" do
    test "are shown once, stored hashed, and stop working when revoked" do
      user = user_fixture()

      {:ok, api_key, "sk_" <> _ = key} = Accounts.create_api_key(user, "  Billing  ")
      assert api_key.name == "Billing"
      assert String.starts_with?(key, api_key.prefix)
      refute api_key.key_hash == key

      assert {:ok, %{id: id, user: %User{}}} = Accounts.authenticate_api_key(key)
      assert id == api_key.id
      assert [_] = Accounts.list_api_keys(user.id)

      other = user_fixture()
      assert {:error, :not_found} = Accounts.revoke_api_key(other.id, api_key.id)
      assert :ok = Accounts.revoke_api_key(user.id, api_key.id)
      assert :error = Accounts.authenticate_api_key(key)
      assert [] = Accounts.list_api_keys(user.id)
    end

    test "need a name" do
      assert {:error, %{name: "is required"}} = Accounts.create_api_key(user_fixture(), " ")
    end
  end

  describe "devices" do
    test "sign in with their token until revoked or the user is suspended" do
      user = user_fixture()

      {:ok, device, "dev_" <> _ = token} =
        Accounts.create_device(user, %{name: "Shop phone", model: "Redmi 12"})

      assert {:ok, %{id: id, user: %User{}}} = Accounts.authenticate_device(token)
      assert id == device.id

      assert {:ok, %{name: "Front desk"}} = Accounts.rename_device(device, "Front desk")
      assert Accounts.get_device(user_fixture().id, device.id) == nil

      {:ok, _} = Accounts.revoke_device(device)
      assert :error = Accounts.authenticate_device(token)
      assert Accounts.list_devices(user.id) == []

      {:ok, _device, token} = Accounts.create_device(user)
      {:ok, _} = Accounts.admin_update_user(user, %{status: "suspended"})
      assert :error = Accounts.authenticate_device(token)
    end
  end

  test "blocked_user_ids/1 lists users who are not approved or over their limit" do
    approved = user_fixture(status: "approved")
    pending = user_fixture()
    limited = user_fixture(status: "approved")
    {:ok, limited} = Accounts.admin_update_user(limited, %{daily_limit: 5})

    blocked = Accounts.blocked_user_ids(%{approved.id => 10, limited.id => 5})

    assert pending.id in blocked
    assert limited.id in blocked
    refute approved.id in blocked
  end

  test "webhook secrets belong to the user's tenant" do
    user = user_fixture()
    assert Accounts.webhook_secret_for_client(User.client(user)) == user.webhook_secret
    assert Accounts.webhook_secret_for_client("test_system") == nil

    rotated = Accounts.rotate_webhook_secret(user)
    refute rotated.webhook_secret == user.webhook_secret
  end
end
