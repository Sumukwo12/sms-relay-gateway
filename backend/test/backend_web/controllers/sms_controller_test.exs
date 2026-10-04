defmodule BackendWeb.SmsControllerTest do
  use BackendWeb.ConnCase, async: false

  import Backend.SmsHelpers

  alias Backend.Modem.Mock

  @phone "+254712345678"

  setup :reset_sms_state

  describe "POST /api/send-code" do
    test "sends a code", %{conn: conn} do
      conn = post(conn, ~p"/api/send-code", %{phone: @phone})

      assert %{"success" => true, "expires_in_seconds" => 300} = json_response(conn, 200)
      assert sent_code(@phone)
    end

    test "422 for an invalid number", %{conn: conn} do
      conn = post(conn, ~p"/api/send-code", %{phone: "0712"})
      assert %{"error" => "invalid_phone"} = json_response(conn, 422)
    end

    test "400 when phone is missing or not a string", %{conn: conn} do
      assert %{"error" => "missing_phone"} =
               conn |> post(~p"/api/send-code", %{}) |> json_response(400)

      assert %{"error" => "missing_phone"} =
               build_conn() |> post(~p"/api/send-code", %{phone: 123}) |> json_response(400)
    end

    test "429 with retry_after_seconds when rate limited", %{conn: conn} do
      for _ <- 1..3, do: post(build_conn(), ~p"/api/send-code", %{phone: @phone})

      conn = post(conn, ~p"/api/send-code", %{phone: @phone})

      assert %{"error" => "rate_limited", "retry_after_seconds" => retry} =
               json_response(conn, 429)

      assert retry > 0
    end

    test "503 when the modem is disconnected", %{conn: conn} do
      Mock.set_status(:disconnected)
      conn = post(conn, ~p"/api/send-code", %{phone: @phone})
      assert %{"error" => "modem_disconnected"} = json_response(conn, 503)
    end

    test "502 when the modem rejects the message", %{conn: conn} do
      Mock.set_status({:failing, {:cms_error, "500"}})
      conn = post(conn, ~p"/api/send-code", %{phone: @phone})
      assert %{"error" => "modem_error"} = json_response(conn, 502)
    end
  end

  describe "POST /api/verify-code" do
    setup do
      post(build_conn(), ~p"/api/send-code", %{phone: @phone})
      %{code: sent_code(@phone)}
    end

    test "verifies the correct code", %{conn: conn, code: code} do
      conn = post(conn, ~p"/api/verify-code", %{phone: @phone, code: code})
      assert %{"success" => true, "verified" => true} = json_response(conn, 200)
    end

    test "422 for a wrong code", %{conn: conn} do
      conn = post(conn, ~p"/api/verify-code", %{phone: @phone, code: "000000x"})
      assert %{"verified" => false, "error" => "invalid_code"} = json_response(conn, 422)
    end

    test "429 after too many wrong codes", %{code: code} do
      bad = if code == "111111", do: "222222", else: "111111"

      for _ <- 1..4 do
        build_conn()
        |> post(~p"/api/verify-code", %{phone: @phone, code: bad})
        |> json_response(422)
      end

      conn = post(build_conn(), ~p"/api/verify-code", %{phone: @phone, code: bad})
      assert %{"error" => "too_many_attempts"} = json_response(conn, 429)
    end

    test "422 when no code is pending", %{conn: conn} do
      conn = post(conn, ~p"/api/verify-code", %{phone: "+254700000009", code: "123456"})
      assert %{"error" => "expired_or_missing"} = json_response(conn, 422)
    end

    test "400 when params are missing", %{conn: conn} do
      conn = post(conn, ~p"/api/verify-code", %{phone: @phone})
      assert %{"error" => "missing_params"} = json_response(conn, 400)
    end
  end

  describe "GET /api/modem/status" do
    test "reports ready", %{conn: conn} do
      assert %{"status" => "ready", "ready" => true} =
               conn |> get(~p"/api/modem/status") |> json_response(200)
    end

    test "reports disconnected", %{conn: conn} do
      Mock.set_status(:disconnected)

      assert %{"status" => "disconnected", "ready" => false} =
               conn |> get(~p"/api/modem/status") |> json_response(200)
    end
  end

  describe "GET /api/rate-limit/:phone" do
    test "returns limit info", %{conn: conn} do
      assert %{"remaining" => 3, "limit" => 3, "retry_after_seconds" => 0} =
               conn |> get("/api/rate-limit/%2B254712345678") |> json_response(200)
    end

    test "422 for an invalid number", %{conn: conn} do
      assert %{"error" => "invalid_phone"} =
               conn |> get("/api/rate-limit/123") |> json_response(422)
    end
  end

  describe "CORS" do
    test "answers preflight requests from the frontend origin", %{conn: conn} do
      conn =
        conn
        |> put_req_header("origin", "http://localhost:3000")
        |> put_req_header("access-control-request-method", "POST")
        |> options("/api/send-code")

      assert conn.status == 204

      assert get_resp_header(conn, "access-control-allow-origin") == [
               "http://localhost:3000"
             ]
    end

    test "does not allow unknown origins", %{conn: conn} do
      conn =
        conn
        |> put_req_header("origin", "https://evil.example")
        |> get(~p"/api/modem/status")

      assert get_resp_header(conn, "access-control-allow-origin") == []
    end
  end
end
