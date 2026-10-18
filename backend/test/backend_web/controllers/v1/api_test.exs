defmodule BackendWeb.V1.ApiTest do
  use BackendWeb.ConnCase, async: false

  import Backend.SmsHelpers

  alias Backend.{Messages, Outbox, Webhooks}

  @phone "+254712345678"

  setup :reset_sms_state
  setup {Req.Test, :set_req_test_to_shared}

  defp authed(conn, key \\ "test-api-key"),
    do: put_req_header(conn, "authorization", "Bearer " <> key)

  describe "authentication" do
    test "rejects missing and unknown keys", %{conn: conn} do
      assert %{"error" => "unauthorized"} = conn |> get(~p"/v1/status") |> json_response(401)
      assert conn |> authed("nope") |> get(~p"/v1/status") |> json_response(401)
    end

    test "accepts X-Api-Key too", %{conn: conn} do
      conn = conn |> put_req_header("x-api-key", "test-api-key") |> get(~p"/v1/status")
      assert json_response(conn, 200)["success"]
    end
  end

  describe "POST /v1/messages" do
    test "queues the message and the outbox sends it", %{conn: conn} do
      body =
        conn
        |> authed()
        |> post(~p"/v1/messages", %{to: @phone, body: "Your order shipped", reference: "order-7"})
        |> json_response(202)

      assert %{
               "success" => true,
               "message" => %{"id" => id, "status" => "queued", "reference" => "order-7"}
             } = body

      refute Map.has_key?(body["message"], "body")

      Outbox.drain()
      assert Backend.Modem.Mock.last_message(@phone).body == "Your order shipped"

      shown = build_conn() |> authed() |> get(~p"/v1/messages/#{id}") |> json_response(200)
      assert %{"message" => %{"status" => "sent", "attempts" => 1}} = shown
    end

    test "validates input", %{conn: conn} do
      body =
        conn
        |> authed()
        |> post(~p"/v1/messages", %{to: "12345", body: "x"})
        |> json_response(422)

      assert %{"error" => "invalid_request", "field" => "to"} = body
    end

    test "rejects new messages at the daily limit", %{conn: conn} do
      original = Application.get_env(:backend, :daily_send_limit)
      Application.put_env(:backend, :daily_send_limit, 0)
      on_exit(fn -> Application.put_env(:backend, :daily_send_limit, original) end)

      body =
        conn |> authed() |> post(~p"/v1/messages", %{to: @phone, body: "x"}) |> json_response(429)

      assert body["error"] == "daily_limit_reached"
    end
  end

  test "GET /v1/messages/:id hides other systems' messages", %{conn: conn} do
    {:ok, message} = Messages.enqueue("test_system", %{to: @phone, body: "x"})

    assert conn
           |> authed("other-api-key")
           |> get(~p"/v1/messages/#{message.id}")
           |> json_response(404)
  end

  describe "OTP" do
    test "send → outbox delivers → verify", %{conn: conn} do
      body = conn |> authed() |> post(~p"/v1/otp/send", %{phone: @phone}) |> json_response(202)

      assert %{"message" => %{"kind" => "otp", "status" => "queued"}, "expires_in_seconds" => 300} =
               body

      Outbox.drain()
      code = sent_code(@phone)
      assert code

      wrong =
        build_conn() |> authed() |> post(~p"/v1/otp/verify", %{phone: @phone, code: "000000"})

      # 000000 could collide with the real code one time in a million
      if code != "000000", do: assert(json_response(wrong, 422)["verified"] == false)

      ok =
        build_conn()
        |> authed()
        |> post(~p"/v1/otp/verify", %{phone: @phone, code: code})
        |> json_response(200)

      assert ok == %{"success" => true, "verified" => true}

      # The stored message no longer contains the code
      assert Messages.get(body["message"]["id"]).body == "[redacted]"
    end

    test "rate limits codes per number", %{conn: conn} do
      for _ <- 1..3,
          do:
            build_conn()
            |> authed()
            |> post(~p"/v1/otp/send", %{phone: @phone})
            |> json_response(202)

      body = conn |> authed() |> post(~p"/v1/otp/send", %{phone: @phone}) |> json_response(429)
      assert %{"error" => "rate_limited", "retry_after_seconds" => _} = body
    end

    test "requires a valid phone", %{conn: conn} do
      assert %{"field" => "phone"} =
               conn |> authed() |> post(~p"/v1/otp/send", %{}) |> json_response(422)

      assert %{"field" => "phone"} =
               build_conn()
               |> authed()
               |> post(~p"/v1/otp/send", %{phone: "abc"})
               |> json_response(422)
    end
  end

  test "GET /v1/status reports modem and queue", %{conn: conn} do
    {:ok, _} = Messages.enqueue("test_system", %{to: @phone, body: "x"})

    body = conn |> authed() |> get(~p"/v1/status") |> json_response(200)

    assert %{
             "modem" => %{"status" => "ready", "ready" => true},
             "queue" => %{"pending" => 1, "sent_last_24h" => 0, "daily_limit" => _}
           } = body
  end

  test "webhooks are signed with the sender's API key", %{conn: conn} do
    test_pid = self()

    Req.Test.stub(Webhooks, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      [signature] = Plug.Conn.get_req_header(conn, "x-signature")
      send(test_pid, {:webhook, raw, signature})
      Req.Test.json(conn, %{ok: true})
    end)

    conn
    |> authed()
    |> post(~p"/v1/messages", %{to: @phone, body: "hi", callback_url: "https://example.test/hook"})
    |> json_response(202)

    Outbox.drain()

    assert_receive {:webhook, raw, signature}, 2_000
    assert %{"event" => "message.sent", "message" => %{"status" => "sent"}} = Jason.decode!(raw)
    assert signature == Webhooks.sign(raw, "test-api-key")
  end

  describe "public /api endpoints" do
    test "can be disabled with PUBLIC_API=false", %{conn: conn} do
      Application.put_env(:backend, :public_api_enabled, false)
      on_exit(fn -> Application.put_env(:backend, :public_api_enabled, true) end)

      assert conn |> post(~p"/api/send-code", %{phone: @phone}) |> json_response(404)
      # Read-only status stays available
      assert build_conn() |> get(~p"/api/modem/status") |> json_response(200)
    end
  end
end
