defmodule BackendWeb.AccountApiTest do
  use BackendWeb.ConnCase, async: false

  import Backend.AccountHelpers
  import Backend.SmsHelpers

  alias Backend.{Accounts, Messages, Outbox, Repo}
  alias Backend.Accounts.User
  alias Backend.Modem.Mock

  @phone "+254712345678"

  setup :reset_sms_state

  defp send_json(conn, method, path, body \\ %{}) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  # Sign in through the API, keeping the session cookie for later requests
  defp sign_in(conn, user) do
    conn
    |> send_json(:post, "/api/auth/login", %{email: user.email, password: password()})
    |> recycle()
  end

  describe "sign-up and sign-in" do
    test "registering signs in with an HttpOnly cookie", %{conn: conn} do
      admin_fixture()

      conn =
        send_json(conn, :post, "/api/auth/register", %{
          email: "dev@example.com",
          password: password(),
          name: "Dev"
        })

      assert %{"user" => %{"email" => "dev@example.com", "status" => "pending", "role" => "user"}} =
               json_response(conn, 201)

      assert %{http_only: true, same_site: "Lax"} = conn.resp_cookies["smsg_session"]

      me = conn |> recycle() |> get("/api/auth/me") |> json_response(200)
      assert me["user"]["email"] == "dev@example.com"
    end

    test "registration errors name the field", %{conn: conn} do
      body =
        conn
        |> send_json(:post, "/api/auth/register", %{email: "x@example.com", password: "short"})
        |> json_response(422)

      assert %{"field" => "password", "message" => "Password must be at least 8 characters"} =
               body
    end

    test "wrong passwords, logout and suspended accounts", %{conn: conn} do
      user = user_fixture()

      assert %{"error" => "invalid_credentials"} =
               conn
               |> send_json(:post, "/api/auth/login", %{email: user.email, password: "nope nope"})
               |> json_response(401)

      conn = sign_in(build_conn(), user)
      assert conn |> get("/api/auth/me") |> json_response(200)

      conn = conn |> send_json(:post, "/api/auth/logout") |> recycle()
      assert conn |> get("/api/auth/me") |> json_response(401)

      {:ok, _} = Accounts.admin_update_user(user, %{status: "suspended"})

      assert %{"error" => "account_suspended"} =
               build_conn()
               |> send_json(:post, "/api/auth/login", %{email: user.email, password: password()})
               |> json_response(403)
    end

    test "dashboard writes must be JSON", %{conn: conn} do
      conn = sign_in(conn, user_fixture())

      assert conn
             |> put_req_header("content-type", "application/x-www-form-urlencoded")
             |> post("/api/account/api-keys", "name=x")
             |> json_response(415)
    end

    test "the dashboard needs a session", %{conn: conn} do
      assert %{"error" => "unauthorized"} = conn |> get("/api/account") |> json_response(401)
    end
  end

  describe "a user's API key" do
    setup %{conn: conn} do
      user = user_fixture()
      conn = sign_in(conn, user)

      %{"key" => key} =
        conn |> send_json(:post, "/api/account/api-keys", %{name: "Shop"}) |> json_response(201)

      %{user: user, conn: recycle(conn), key: key}
    end

    defp v1(key), do: build_conn() |> put_req_header("authorization", "Bearer " <> key)

    test "can't send until the account is approved", %{user: user, key: key} do
      assert %{"error" => "account_pending"} =
               key
               |> v1()
               |> post("/v1/messages", %{to: @phone, body: "hi"})
               |> json_response(403)

      # Reading is fine while pending
      assert %{"account" => %{"status" => "pending"}} =
               key |> v1() |> get("/v1/status") |> json_response(200)

      {:ok, _} = Accounts.admin_update_user(user, %{status: "approved"})
      assert key |> v1() |> post("/v1/messages", %{to: @phone, body: "hi"}) |> json_response(202)
    end

    test "messages belong to the user and count against their own limit", %{user: user, key: key} do
      {:ok, user} = Accounts.admin_update_user(user, %{status: "approved", daily_limit: 1})

      %{"message" => %{"id" => id}} =
        key |> v1() |> post("/v1/messages", %{to: @phone, body: "hi"}) |> json_response(202)

      message = Messages.get(id)
      assert message.user_id == user.id
      assert message.client == User.client(user)

      # The second exceeds the user's limit of 1 part per day
      assert %{"error" => "daily_limit_reached"} =
               key
               |> v1()
               |> post("/v1/messages", %{to: @phone, body: "again"})
               |> json_response(429)

      # Server keys don't see the user's messages, and vice versa
      assert build_conn()
             |> put_req_header("authorization", "Bearer test-api-key")
             |> get("/v1/messages/#{id}")
             |> json_response(404)

      Outbox.drain()
      assert Mock.last_message(@phone).body == "hi"
      assert %{status: "sent"} = Messages.get(id)
    end

    test "device_id must be one of the user's phones", %{user: user, key: key} do
      {:ok, _} = Accounts.admin_update_user(user, %{status: "approved"})
      {:ok, device, _token} = Accounts.create_device(user)
      {:ok, others, _token} = Accounts.create_device(user_fixture())

      assert %{"field" => "device_id"} =
               key
               |> v1()
               |> post("/v1/messages", %{to: @phone, body: "hi", device_id: others.id})
               |> json_response(422)

      %{"message" => %{"device_id" => device_id}} =
        key
        |> v1()
        |> post("/v1/messages", %{to: @phone, body: "hi", device_id: device.id})
        |> json_response(202)

      assert device_id == device.id
    end

    test "OTP codes are scoped to the user", %{user: user, key: key} do
      {:ok, _} = Accounts.admin_update_user(user, %{status: "approved"})

      assert key |> v1() |> post("/v1/otp/send", %{phone: @phone}) |> json_response(202)
      Outbox.drain()
      code = sent_code(@phone)

      # Another tenant can't verify it
      assert build_conn()
             |> put_req_header("authorization", "Bearer test-api-key")
             |> post("/v1/otp/verify", %{phone: @phone, code: code})
             |> json_response(422)

      assert %{"verified" => true} =
               key
               |> v1()
               |> post("/v1/otp/verify", %{phone: @phone, code: code})
               |> json_response(200)
    end

    test "is listed without the secret and can be revoked", %{conn: conn, key: key} do
      assert %{"api_keys" => [%{"id" => id, "name" => "Shop", "prefix" => prefix} = listed]} =
               conn |> get("/api/account/api-keys") |> json_response(200)

      assert String.starts_with?(key, prefix)
      refute Map.has_key?(listed, "key")

      conn |> recycle() |> send_json(:delete, "/api/account/api-keys/#{id}") |> json_response(200)
      assert key |> v1() |> get("/v1/status") |> json_response(401)
    end
  end

  describe "dashboard" do
    test "overview, phones and the test console", %{conn: conn} do
      user = user_fixture(status: "approved")
      {:ok, device, _token} = Accounts.create_device(user, %{name: "Shop phone"})
      conn = sign_in(conn, user)

      overview = conn |> get("/api/account") |> json_response(200)

      assert %{
               "user" => %{"status" => "approved", "daily_limit" => 200},
               "usage" => %{"sent_last_24h" => 0, "queued" => 0},
               "devices" => [%{"name" => "Shop phone", "online" => false}],
               "webhook_secret" => "whsec_" <> _
             } = overview

      assert %{"device" => %{"name" => "Desk"}} =
               conn
               |> recycle()
               |> send_json(:patch, "/api/account/devices/#{device.id}", %{name: "Desk"})
               |> json_response(200)

      assert %{"message" => %{"id" => id, "status" => "queued"}} =
               conn
               |> recycle()
               |> send_json(:post, "/api/account/console/sms", %{to: @phone, body: "Test"})
               |> json_response(202)

      assert Messages.get(id).user_id == user.id

      assert %{"messages" => [%{"id" => ^id}]} =
               conn |> recycle() |> get("/api/account/messages") |> json_response(200)

      conn
      |> recycle()
      |> send_json(:delete, "/api/account/devices/#{device.id}")
      |> json_response(200)

      assert Accounts.list_devices(user.id) == []
    end

    test "console OTP send and verify", %{conn: conn} do
      conn = sign_in(conn, user_fixture(status: "approved"))

      assert %{"expires_in_seconds" => _} =
               conn
               |> send_json(:post, "/api/account/console/otp/send", %{phone: @phone})
               |> json_response(202)

      Outbox.drain()

      assert %{"verified" => false, "error" => "invalid_code"} =
               conn
               |> recycle()
               |> send_json(:post, "/api/account/console/otp/verify", %{
                 phone: @phone,
                 code: "000000"
               })
               |> json_response(422)

      assert %{"verified" => true} =
               conn
               |> recycle()
               |> send_json(:post, "/api/account/console/otp/verify", %{
                 phone: @phone,
                 code: sent_code(@phone)
               })
               |> json_response(200)
    end

    test "pending accounts can't use the console", %{conn: conn} do
      conn = sign_in(conn, user_fixture())

      assert %{"error" => "account_pending"} =
               conn
               |> send_json(:post, "/api/account/console/sms", %{to: @phone, body: "Test"})
               |> json_response(403)
    end

    test "change password and rotate the webhook secret", %{conn: conn} do
      user = user_fixture()
      conn = sign_in(conn, user)

      assert %{"field" => "current_password"} =
               conn
               |> send_json(:post, "/api/account/password", %{
                 current_password: "wrong",
                 new_password: "another password"
               })
               |> json_response(422)

      assert %{"webhook_secret" => secret} =
               conn
               |> recycle()
               |> send_json(:post, "/api/account/webhook-secret")
               |> json_response(200)

      assert Repo.get(User, user.id).webhook_secret == secret
      refute secret == user.webhook_secret
    end
  end

  describe "admin" do
    test "is for admins only", %{conn: conn} do
      conn = sign_in(conn, user_fixture(status: "approved"))
      assert %{"error" => "forbidden"} = conn |> get("/api/admin/users") |> json_response(403)
    end

    test "sees every user's messages with their owner", %{conn: conn} do
      admin = admin_fixture()
      user = user_fixture(status: "approved")

      {:ok, message} =
        Messages.enqueue(User.client(user), %{to: @phone, body: "hi"}, user_id: user.id)

      {:ok, _} = Messages.enqueue("test_system", %{to: @phone, body: "server"})

      assert %{"messages" => messages} =
               conn |> sign_in(admin) |> get("/api/admin/messages") |> json_response(200)

      assert %{"owner" => owner} = Enum.find(messages, &(&1["id"] == message.id))
      assert owner == user.email
      assert Enum.any?(messages, &(&1["owner"] == "test_system"))
    end

    test "approves, suspends and limits users", %{conn: conn} do
      admin = admin_fixture()
      user = user_fixture()
      conn = sign_in(conn, admin)

      assert %{"users" => users} = conn |> get("/api/admin/users") |> json_response(200)
      assert Enum.any?(users, &(&1["id"] == user.id and &1["status"] == "pending"))

      assert %{"user" => %{"status" => "approved", "daily_limit" => 50}} =
               conn
               |> recycle()
               |> send_json(:patch, "/api/admin/users/#{user.id}", %{
                 status: "approved",
                 daily_limit: 50
               })
               |> json_response(200)

      assert %{"field" => "status"} =
               conn
               |> recycle()
               |> send_json(:patch, "/api/admin/users/#{user.id}", %{status: "banana"})
               |> json_response(422)

      assert conn
             |> recycle()
             |> send_json(:patch, "/api/admin/users/#{admin.id}", %{role: "user"})
             |> json_response(422)

      assert %{"users" => %{"approved" => _}, "devices" => %{"online" => 0}} =
               conn |> recycle() |> get("/api/admin/overview") |> json_response(200)

      assert %{"devices" => []} =
               conn |> recycle() |> get("/api/admin/devices") |> json_response(200)
    end
  end

  describe "SMS Relay app sign-in" do
    test "links the phone and returns its token", %{conn: conn} do
      user = user_fixture()

      body =
        conn
        |> send_json(:post, "/api/app/login", %{
          email: user.email,
          password: password(),
          device_name: "Shop phone",
          model: "Redmi 12",
          app_version: "1.1.0"
        })
        |> json_response(200)

      assert %{
               "device_token" => "dev_" <> _ = token,
               "device" => %{"name" => "Shop phone", "model" => "Redmi 12"},
               "user" => %{"status" => "pending"},
               "socket_url" => "ws" <> _
             } = body

      app = fn -> build_conn() |> put_req_header("authorization", "Bearer " <> token) end

      assert %{"device" => %{"name" => "Shop phone"}} =
               app.() |> get("/api/app/me") |> json_response(200)

      app.() |> send_json(:post, "/api/app/logout") |> json_response(200)
      assert app.() |> get("/api/app/me") |> json_response(401)
    end

    test "rejects wrong passwords", %{conn: conn} do
      user = user_fixture()

      assert conn
             |> send_json(:post, "/api/app/login", %{email: user.email, password: "wrong pass"})
             |> json_response(401)
    end
  end
end
