defmodule Backend.MonitorTest do
  use Backend.DataCase, async: false

  import Backend.SmsHelpers
  alias Backend.{Messages, Monitor, Repo}
  alias Backend.Modem.Mock

  @phone "+254712345678"

  setup {Req.Test, :set_req_test_to_shared}

  setup do
    reset_sms_state()
    test_pid = self()

    Req.Test.stub(Monitor, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:alert, Jason.decode!(raw)})
      Req.Test.json(conn, %{})
    end)

    put_envs(
      alert_webhook_url: "https://alerts.example.test/hook",
      alert_req_options: [plug: {Req.Test, Monitor}, retry: false],
      alert_offline_seconds: 0,
      alert_queue_age_seconds: 60
    )

    # Start each test from a clean slate (no alerts firing)
    Monitor.check_now()
    flush_alerts()
    :ok
  end

  defp put_envs(envs) do
    for {key, value} <- envs do
      original = Application.get_env(:backend, key)
      Application.put_env(:backend, key, value)
      on_exit(fn -> Application.put_env(:backend, key, original) end)
    end
  end

  defp flush_alerts do
    receive do
      {:alert, _} -> flush_alerts()
    after
      50 -> :ok
    end
  end

  test "alerts once when the modem goes offline and once when it recovers" do
    Mock.set_status(:disconnected)

    assert %{"modem_offline" => _} = Monitor.check_now()
    assert_receive {:alert, %{"alert" => "modem_offline", "status" => "firing", "text" => _}}

    # Still offline: no repeat
    Monitor.check_now()
    refute_receive {:alert, _}, 100

    Mock.set_status(:ready)
    assert Monitor.check_now() == %{}
    assert_receive {:alert, %{"alert" => "modem_offline", "status" => "resolved"}}
  end

  test "alerts when a message has waited too long in the queue" do
    {:ok, message} = Messages.enqueue("test_system", %{to: @phone, body: "hi"})

    Repo.update_all(Messages.Message,
      set: [inserted_at: DateTime.add(DateTime.utc_now(), -120, :second)]
    )

    assert %{"queue_stuck" => text} = Monitor.check_now()
    assert text =~ "1 message(s) waiting"
    assert message.status == "queued"
  end

  test "alerts when 90% of the daily cap is used" do
    put_envs(daily_send_limit: 10)
    for _ <- 1..9, do: Messages.record_direct_send("public", "otp", @phone, "code")

    assert %{"daily_limit_near" => "9 of 10 daily SMS parts used in the last 24h."} =
             Monitor.check_now()
  end
end
