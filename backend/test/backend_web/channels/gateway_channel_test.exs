defmodule BackendWeb.GatewayChannelTest do
  use BackendWeb.ChannelCase, async: false

  alias Backend.Modem.Phone, as: PhoneModem
  alias BackendWeb.{GatewayChannel, PhoneSocket}

  @valid_token "test_secret_token"

  setup do
    phone_pid = start_supervised!(PhoneModem)
    original_token = Application.get_env(:backend, :phone_gateway_token)
    Application.put_env(:backend, :phone_gateway_token, @valid_token)

    on_exit(fn ->
      if original_token do
        Application.put_env(:backend, :phone_gateway_token, original_token)
      else
        Application.delete_env(:backend, :phone_gateway_token)
      end
    end)

    {:ok, modem: phone_pid}
  end

  defp connect_phone_socket(token \\ @valid_token) do
    {:ok, socket} = connect(PhoneSocket, %{"token" => token})
    socket
  end

  test "join rejects bad token with invalid_token and does not register phone" do
    socket = connect_phone_socket("wrong_token")

    assert {:error, %{reason: "invalid_token"}} =
             subscribe_and_join(socket, GatewayChannel, "gateway:phone")

    assert PhoneModem.status() == :disconnected
  end

  test "join rejects when phone_gateway_token is unset or empty" do
    Application.delete_env(:backend, :phone_gateway_token)
    socket = connect_phone_socket(@valid_token)

    assert {:error, %{reason: "invalid_token"}} =
             subscribe_and_join(socket, GatewayChannel, "gateway:phone")

    assert PhoneModem.status() == :disconnected

    Application.put_env(:backend, :phone_gateway_token, "")

    assert {:error, %{reason: "invalid_token"}} =
             subscribe_and_join(socket, GatewayChannel, "gateway:phone")

    assert PhoneModem.status() == :disconnected
  end

  test "status/0 is :disconnected with no phone" do
    assert PhoneModem.status() == :disconnected
  end

  test "status/0 is :ready when phone joins and reverts to :disconnected on leave" do
    assert PhoneModem.status() == :disconnected

    {:ok, _, socket} =
      connect_phone_socket()
      |> subscribe_and_join(GatewayChannel, "gateway:phone")

    assert PhoneModem.status() == :ready

    Process.unlink(socket.channel_pid)
    ref = Process.monitor(socket.channel_pid)
    Process.exit(socket.channel_pid, :shutdown)
    assert_receive {:DOWN, ^ref, :process, _, _}

    _ = :sys.get_state(PhoneModem)
    assert PhoneModem.status() == :disconnected
  end

  test "send succeeds on sent" do
    {:ok, _, socket} =
      connect_phone_socket()
      |> subscribe_and_join(GatewayChannel, "gateway:phone")

    task = Task.async(fn -> PhoneModem.send_sms("+254712345678", "OTP: 123456") end)

    assert_push "send_sms", %{"id" => id, "to" => "+254712345678", "body" => "OTP: 123456"}

    push(socket, "sms_result", %{"id" => id, "status" => "sent"})

    assert Task.await(task) == :ok
  end

  test "send fails on failed" do
    {:ok, _, socket} =
      connect_phone_socket()
      |> subscribe_and_join(GatewayChannel, "gateway:phone")

    task = Task.async(fn -> PhoneModem.send_sms("+254712345678", "OTP: 999999") end)

    assert_push "send_sms", %{"id" => id, "to" => "+254712345678", "body" => "OTP: 999999"}

    push(socket, "sms_result", %{
      "id" => id,
      "status" => "failed",
      "error" => "No airtime remaining"
    })

    assert Task.await(task) == {:error, "No airtime remaining"}
  end

  test "timeout" do
    stop_supervised!(PhoneModem)
    start_supervised!({PhoneModem, send_timeout_ms: 50})

    {:ok, _, _socket} =
      connect_phone_socket()
      |> subscribe_and_join(GatewayChannel, "gateway:phone")

    task = Task.async(fn -> PhoneModem.send_sms("+254712345678", "OTP: timeout") end)

    assert_push "send_sms", %{"id" => _id}

    assert Task.await(task) == {:error, :send_timeout}
  end

  test "disconnect mid-send" do
    {:ok, _, socket} =
      connect_phone_socket()
      |> subscribe_and_join(GatewayChannel, "gateway:phone")

    task = Task.async(fn -> PhoneModem.send_sms("+254712345678", "OTP: disconnect") end)

    assert_push "send_sms", %{"id" => _id}

    Process.unlink(socket.channel_pid)
    ref = Process.monitor(socket.channel_pid)
    Process.exit(socket.channel_pid, :kill)
    assert_receive {:DOWN, ^ref, :process, _, _}

    assert Task.await(task) == {:error, :modem_disconnected}
    assert PhoneModem.status() == :disconnected
  end

  test "newest connection wins" do
    {:ok, _, socket1} =
      connect_phone_socket()
      |> subscribe_and_join(GatewayChannel, "gateway:phone")

    ref1 = Process.monitor(socket1.channel_pid)
    Process.unlink(socket1.channel_pid)
    assert PhoneModem.status() == :ready

    # Start a send pending on phone 1
    task1 = Task.async(fn -> PhoneModem.send_sms("+254711111111", "Message 1") end)
    assert_push "send_sms", %{"id" => _id1, "to" => "+254711111111"}

    # Phone 2 connects and joins
    {:ok, _, socket2} =
      connect_phone_socket()
      |> subscribe_and_join(GatewayChannel, "gateway:phone")

    # Phone 1 is terminated
    assert_receive {:DOWN, ^ref1, :process, _, _}

    # Phone 1's pending send fails with :modem_disconnected
    assert Task.await(task1) == {:error, :modem_disconnected}

    # Phone 2 is the active phone and can send
    task2 = Task.async(fn -> PhoneModem.send_sms("+254722222222", "Message 2") end)
    assert_push "send_sms", %{"id" => id2, "to" => "+254722222222"}

    push(socket2, "sms_result", %{"id" => id2, "status" => "sent"})
    assert Task.await(task2) == :ok
  end

  test "sms_delivered and device_info" do
    {:ok, _, socket} =
      connect_phone_socket()
      |> subscribe_and_join(GatewayChannel, "gateway:phone")

    push(socket, "sms_delivered", %{"id" => "deliv-123"})

    push(socket, "device_info", %{
      "battery" => 85,
      "signal" => 4,
      "app_version" => "1.0.0"
    })

    # Both pushes are handled by the channel first, then forwarded to the modem
    _ = :sys.get_state(socket.channel_pid)
    _ = :sys.get_state(PhoneModem)

    assert PhoneModem.get_device_info() == %{
             "battery" => 85,
             "signal" => 4,
             "app_version" => "1.0.0"
           }
  end

  describe "outbox delivery reports" do
    setup do
      {:ok, message} = Backend.Messages.enqueue("test_system", %{to: "+254712345678", body: "hi"})
      {:ok, message: message}
    end

    test "sms_delivered marks the outbox message delivered", %{message: message} do
      {:ok, _, socket} =
        connect_phone_socket() |> subscribe_and_join(GatewayChannel, "gateway:phone")

      ref = push(socket, "sms_delivered", %{"id" => message.id})
      # The ack lets the app drop the report from its retry buffer
      assert_reply ref, :ok

      assert %{status: "delivered"} = Backend.Messages.get(message.id)
    end

    test "a late sms_result still marks the message sent", %{message: message} do
      Backend.Messages.checkout_next()
      {:ok, _} = Backend.Messages.fail(message.id, :send_timeout)

      {:ok, _, socket} =
        connect_phone_socket() |> subscribe_and_join(GatewayChannel, "gateway:phone")

      push(socket, "sms_result", %{"id" => message.id, "status" => "sent"})
      _ = :sys.get_state(socket.channel_pid)

      assert %{status: "sent"} = Backend.Messages.get(message.id)
    end
  end
end
