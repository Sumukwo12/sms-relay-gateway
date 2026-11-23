defmodule BackendWeb.V1.IntegrationFeaturesTest do
  @moduledoc "Test keys, OTP options, local numbers and the account webhook URL."
  use BackendWeb.ConnCase, async: false

  import Backend.AccountHelpers
  import Backend.SmsHelpers

  alias Backend.{Accounts, Messages, Outbox, Webhooks}
  alias Backend.Modem.Mock

  @phone "+254712345678"

  setup :reset_sms_state
  setup {Req.Test, :set_req_test_to_shared}

  defp v1(key), do: build_conn() |> put_req_header("authorization", "Bearer " <> key)

  defp key!(user, mode \\ "live") do
    {:ok, _api_key, key} = Accounts.create_api_key(user, "Test system", mode)
    key
  end

  describe "test keys" do
    test "simulate OTP: nothing is sent, the code comes back and verifies" do
      # Even a pending account can integrate with a test key
      user = user_fixture()
      key = key!(user, "test")
      assert "sk_test_" <> _ = key

      body = key |> v1() |> post("/v1/otp/send", %{phone: @phone}) |> json_response(202)

      assert %{
               "test_code" => code,
               "message" => %{"id" => id, "status" => "delivered", "test" => true}
             } = body

      assert Mock.outbox() == []
      assert Outbox.drain() == 0
      assert Messages.sent_last_24h(user.id) == 0

      assert %{"verified" => true} =
               key
               |> v1()
               |> post("/v1/otp/verify", %{phone: @phone, code: code})
               |> json_response(200)

      assert %{"message" => %{"status" => "delivered"}} =
               key |> v1() |> get("/v1/messages/#{id}") |> json_response(200)
    end

    test "simulate notifications and their webhooks" do
      user = user_fixture()
      key = key!(user, "test")
      test_pid = self()

      Req.Test.stub(Webhooks, fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:webhook, Jason.decode!(raw)["event"]})
        Req.Test.json(conn, %{ok: true})
      end)

      assert %{"message" => %{"status" => "delivered", "test" => true}} =
               key
               |> v1()
               |> post("/v1/messages", %{
                 to: @phone,
                 body: "hi",
                 callback_url: "https://example.com/hook"
               })
               |> json_response(202)

      Webhooks.drain()
      Webhooks.drain()
      assert_receive {:webhook, "message.sent"}, 2_000
      assert_receive {:webhook, "message.delivered"}, 2_000
      assert Mock.outbox() == []
    end

    test "live keys of pending accounts still can't send" do
      assert %{"error" => "account_pending"} =
               user_fixture()
               |> key!()
               |> v1()
               |> post("/v1/messages", %{to: @phone, body: "hi"})
               |> json_response(403)
    end
  end

  describe "OTP options" do
    setup do
      user = user_fixture(status: "approved")
      %{user: user, key: key!(user)}
    end

    test "custom template, code length and expiry", %{key: key} do
      body =
        key
        |> v1()
        |> post("/v1/otp/send", %{
          phone: @phone,
          template: "Your Acme code is {code}. It expires in {minutes} min.",
          code_length: 4,
          expires_in: 120
        })
        |> json_response(202)

      assert body["expires_in_seconds"] in 118..120
      refute Map.has_key?(body, "test_code")

      Outbox.drain()
      sms = Mock.last_message(@phone).body
      assert sms =~ ~r/^Your Acme code is \d{4}\. It expires in 2 min\.$/
    end

    test "the account's default template", %{user: user, key: key} do
      {:ok, _} = Accounts.update_settings(user, %{otp_template: "Shop code: {code}"})
      key |> v1() |> post("/v1/otp/send", %{phone: @phone}) |> json_response(202)
      Outbox.drain()
      assert Mock.last_message(@phone).body =~ ~r/^Shop code: \d{6}$/
    end

    test "rejects bad options", %{key: key} do
      for {params, field} <- [
            {%{template: "no placeholder"}, "template"},
            {%{code_length: 3}, "code_length"},
            {%{code_length: "nine"}, "code_length"},
            {%{expires_in: 10}, "expires_in"}
          ] do
        assert %{"field" => ^field} =
                 key
                 |> v1()
                 |> post("/v1/otp/send", Map.put(params, :phone, @phone))
                 |> json_response(422)
      end
    end

    test "local number formats", %{key: key} do
      assert %{"message" => %{"to" => @phone}} =
               key
               |> v1()
               |> post("/v1/messages", %{to: "0712 345 678", body: "hi"})
               |> json_response(202)
    end
  end

  describe "account webhook URL" do
    test "receives message events when the request has no callback_url" do
      user = user_fixture(status: "approved")

      {:ok, _} =
        Accounts.update_settings(user, %{webhook_url: "https://example.com/account-hook"})

      test_pid = self()

      Req.Test.stub(Webhooks, fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:webhook, conn.host, conn.request_path, Jason.decode!(raw)["event"]})
        Req.Test.json(conn, %{ok: true})
      end)

      user
      |> key!()
      |> v1()
      |> post("/v1/messages", %{to: @phone, body: "hi"})
      |> json_response(202)

      Outbox.drain()
      Webhooks.drain()

      assert_receive {:webhook, "example.com", "/account-hook", "message.sent"}, 2_000
    end

    test "settings are validated and can be cleared" do
      user = user_fixture()

      assert {:error, %{webhook_url: "must be an http(s) URL"}} =
               Accounts.update_settings(user, %{webhook_url: "ftp://x"})

      assert {:error, %{otp_template: "must contain {code}"}} =
               Accounts.update_settings(user, %{otp_template: "hello"})

      {:ok, user} = Accounts.update_settings(user, %{webhook_url: " https://a.example/h "})
      assert user.webhook_url == "https://a.example/h"
      {:ok, user} = Accounts.update_settings(user, %{webhook_url: ""})
      assert user.webhook_url == nil
    end
  end
end
