defmodule Backend.SmsGatewayTest do
  use ExUnit.Case, async: false

  import Backend.SmsHelpers

  alias Backend.{CodeStore, SmsGateway}
  alias Backend.Modem.Mock

  @phone "+254712345678"

  setup :reset_sms_state

  describe "send_verification_code/1" do
    test "sends a 6-digit code over the modem and stores it" do
      assert {:ok, :sent} = SmsGateway.send_verification_code(@phone)

      assert sent_code(@phone) =~ ~r/^\d{6}$/
      assert CodeStore.has_pending?(@phone)
    end

    test "normalises spaces, dashes and parentheses" do
      assert {:ok, :sent} = SmsGateway.send_verification_code(" +254 (712) 345-678 ")
      assert sent_code(@phone)
    end

    test "rejects numbers that are not E.164" do
      for bad <- ["0712345678", "+0712345678", "+123", "abc", "", nil, 254_712_345_678] do
        assert {:error, :invalid_phone} = SmsGateway.send_verification_code(bad)
      end

      assert Mock.outbox() == []
    end

    test "rate limits after the configured number of sends per hour" do
      for _ <- 1..3, do: assert({:ok, :sent} = SmsGateway.send_verification_code(@phone))

      assert {:error, :rate_limited, retry_after} = SmsGateway.send_verification_code(@phone)
      assert retry_after > 0 and retry_after <= 3_600
      assert length(Mock.outbox()) == 3
    end

    test "rate limits are per phone number" do
      for _ <- 1..3, do: SmsGateway.send_verification_code(@phone)

      assert {:ok, :sent} = SmsGateway.send_verification_code("+254700000001")
    end

    test "concurrent requests to the same number: at most limit succeed" do
      # Fire 20 parallel requests to @phone
      tasks =
        for _ <- 1..20 do
          Task.async(fn ->
            SmsGateway.send_verification_code(@phone)
          end)
        end

      results = Task.await_many(tasks)
      successful = Enum.count(results, &(&1 == {:ok, :sent}))
      rate_limited = Enum.count(results, &match?({:error, :rate_limited, _}, &1))

      assert successful == 3
      assert rate_limited == 17
      assert successful + rate_limited == 20
    end

    test "enforces per-client-IP rate limit" do
      ip = "198.51.100.5"

      for i <- 1..5 do
        phone = "+25470000000#{i}"
        assert {:ok, :sent} = SmsGateway.send_verification_code(phone, client_ip: ip)
      end

      # 6th send with the same IP must be rate limited even with a fresh phone number
      assert {:error, :rate_limited, retry_after} =
               SmsGateway.send_verification_code("+254700000099", client_ip: ip)

      assert retry_after > 0
    end

    test "enforces global rate limit cap" do
      Application.put_env(:backend, :rate_limit_global_per_hour, 10)
      on_exit(fn -> Application.put_env(:backend, :rate_limit_global_per_hour, 100) end)

      for i <- 1..10 do
        phone = "+25471100000#{i}"
        assert {:ok, :sent} = SmsGateway.send_verification_code(phone, client_ip: "10.0.0.#{i}")
      end

      # 11th send must be rate limited by global cap
      assert {:error, :rate_limited, _} =
               SmsGateway.send_verification_code("+254799999999", client_ip: "10.0.0.99")
    end

    test "reports a disconnected modem without storing a code or using up the rate limit" do
      Mock.set_status(:disconnected)

      assert {:error, :modem_disconnected} = SmsGateway.send_verification_code(@phone)
      refute CodeStore.has_pending?(@phone)
      assert {:ok, %{remaining: 3}} = SmsGateway.rate_limit_info(@phone)
    end

    test "wraps other modem failures as :modem_error" do
      Mock.set_status({:failing, {:cms_error, "500"}})

      assert {:error, :modem_error, {:cms_error, "500"}} =
               SmsGateway.send_verification_code(@phone)

      refute CodeStore.has_pending?(@phone)
    end
  end

  describe "verify_code/2" do
    setup do
      {:ok, :sent} = SmsGateway.send_verification_code(@phone)
      %{code: sent_code(@phone)}
    end

    test "accepts the correct code once", %{code: code} do
      assert :ok = SmsGateway.verify_code(@phone, code)
      assert {:error, :expired_or_missing} = SmsGateway.verify_code(@phone, code)
    end

    test "tolerates surrounding whitespace", %{code: code} do
      assert :ok = SmsGateway.verify_code(@phone, " #{code} ")
    end

    test "rejects a wrong code but keeps the real one valid", %{code: code} do
      assert {:error, :invalid_code} = SmsGateway.verify_code(@phone, wrong(code))
      assert :ok = SmsGateway.verify_code(@phone, code)
    end

    test "discards the code after too many wrong guesses", %{code: code} do
      for _ <- 1..4 do
        assert {:error, :invalid_code} = SmsGateway.verify_code(@phone, wrong(code))
      end

      assert {:error, :too_many_attempts} = SmsGateway.verify_code(@phone, wrong(code))
      assert {:error, :expired_or_missing} = SmsGateway.verify_code(@phone, code)
    end

    test "50 parallel wrong guesses yield at most max_verify_attempts invalid_code responses and then too_many_attempts / expired_or_missing" do
      max_attempts = Application.get_env(:backend, :max_verify_attempts, 5)

      tasks =
        for _ <- 1..50 do
          Task.async(fn ->
            SmsGateway.verify_code(@phone, "000000")
          end)
        end

      results = Task.await_many(tasks)

      invalid_count = Enum.count(results, &(&1 == {:error, :invalid_code}))
      too_many_count = Enum.count(results, &(&1 == {:error, :too_many_attempts}))
      expired_or_missing_count = Enum.count(results, &(&1 == {:error, :expired_or_missing}))

      assert invalid_count <= max_attempts
      assert invalid_count + too_many_count + expired_or_missing_count == 50
      assert too_many_count + expired_or_missing_count > 0
    end

    test "a new code replaces the previous one", %{code: first} do
      {:ok, :sent} = SmsGateway.send_verification_code(@phone)
      second = sent_code(@phone)

      if first != second do
        assert {:error, :invalid_code} = SmsGateway.verify_code(@phone, first)
      end

      assert :ok = SmsGateway.verify_code(@phone, second)
    end

    test "returns :expired_or_missing for unknown or invalid numbers" do
      assert {:error, :expired_or_missing} = SmsGateway.verify_code("+254799999999", "123456")
      assert {:error, :expired_or_missing} = SmsGateway.verify_code("nope", "123456")
    end
  end

  describe "rate_limit_info/1" do
    test "reports remaining sends and retry time" do
      assert {:ok, %{remaining: 3, limit: 3, retry_after_seconds: 0}} =
               SmsGateway.rate_limit_info(@phone)

      for _ <- 1..3, do: SmsGateway.send_verification_code(@phone)

      assert {:ok, %{remaining: 0, retry_after_seconds: retry}} =
               SmsGateway.rate_limit_info(@phone)

      assert retry > 0
    end

    test "rejects invalid numbers" do
      assert {:error, :invalid_phone} = SmsGateway.rate_limit_info("123")
    end
  end

  test "code_generator produces zero-padded codes of the requested length" do
    for len <- [4, 6, 8] do
      code = Backend.CodeGenerator.generate(len)
      assert String.length(code) == len
      assert code =~ ~r/^\d+$/
    end
  end

  defp wrong(code) do
    code
    |> String.to_integer()
    |> Kernel.+(1)
    |> rem(1_000_000)
    |> Integer.to_string()
    |> String.pad_leading(6, "0")
  end
end
