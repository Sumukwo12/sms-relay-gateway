defmodule BackendWeb.GatewayDevicesTest do
  @moduledoc "Several users' phones connected at once, signed in with device tokens."
  use BackendWeb.ChannelCase, async: false

  import Backend.AccountHelpers

  alias Backend.{Accounts, Messages}
  alias Backend.Modem.Phone, as: PhoneModem
  alias BackendWeb.{GatewayChannel, PhoneSocket}

  @legacy_token "legacy_secret_token"

  setup do
    start_supervised!(PhoneModem)
    Application.put_env(:backend, :phone_gateway_token, @legacy_token)
    on_exit(fn -> Application.delete_env(:backend, :phone_gateway_token) end)

    alice = user_fixture(status: "approved")
    bob = user_fixture(status: "approved")
    {:ok, alice_phone, alice_token} = Accounts.create_device(alice, %{name: "Alice's phone"})
    {:ok, _bob_phone, bob_token} = Accounts.create_device(bob)

    %{
      alice: alice,
      bob: bob,
      alice_phone: alice_phone,
      alice_token: alice_token,
      bob_token: bob_token
    }
  end

  defp join(token, payload \\ %{}) do
    {:ok, socket} = connect(PhoneSocket, %{"token" => token})
    {:ok, _, socket} = subscribe_and_join(socket, GatewayChannel, "gateway:phone", payload)
    Process.unlink(socket.channel_pid)
    socket
  end

  defp send_async(opts),
    do: Task.async(fn -> PhoneModem.send_sms("+254712345678", "Hi", opts) end)

  test "each user's messages go only to their own phone", ctx do
    alice = join(ctx.alice_token)
    bob = join(ctx.bob_token)

    assert PhoneModem.status(ctx.alice.id) == :ready
    assert PhoneModem.status(ctx.bob.id) == :ready
    # No legacy or admin phone: server-level messages can't go out
    assert PhoneModem.status() == :disconnected

    assert %{users: users, system: false} = PhoneModem.available_owners()
    assert MapSet.equal?(users, MapSet.new([ctx.alice.id, ctx.bob.id]))

    task = send_async(id: "for-alice", user_id: ctx.alice.id)
    assert_push "send_sms", %{"id" => "for-alice"}

    # Bob's phone can't answer for Alice's message
    push(bob, "sms_result", %{"id" => "for-alice", "status" => "sent"})
    _ = :sys.get_state(bob.channel_pid)
    assert Task.yield(task, 50) == nil

    push(alice, "sms_result", %{"id" => "for-alice", "status" => "sent"})
    assert Task.await(task) == :ok

    assert {:error, :modem_disconnected} =
             PhoneModem.send_sms("+254712345678", "Hi", user_id: user_fixture().id)
  end

  test "the legacy token and admins' phones carry server-level messages", _ctx do
    assert PhoneModem.status() == :disconnected

    admin = admin_fixture()
    {:ok, _device, admin_token} = Accounts.create_device(admin)
    join(admin_token)
    assert PhoneModem.status() == :ready

    legacy = join(@legacy_token)

    # The legacy phone is preferred for server-level messages
    task = send_async(id: "system-msg")
    assert_push "send_sms", %{"id" => "system-msg"}
    push(legacy, "sms_result", %{"id" => "system-msg", "status" => "sent"})
    assert Task.await(task) == :ok
  end

  test "a probe join checks a device token without registering it", ctx do
    {:ok, socket} = connect(PhoneSocket, %{"token" => ctx.alice_token})

    assert {:ok, _, _} =
             subscribe_and_join(socket, GatewayChannel, "gateway:phone", %{"probe" => true})

    assert PhoneModem.status(ctx.alice.id) == :disconnected
  end

  test "a device reconnecting replaces only its own older connection", ctx do
    {:ok, second_phone, second_token} = Accounts.create_device(ctx.alice)

    first = join(ctx.alice_token)
    first_ref = Process.monitor(first.channel_pid)
    other = join(second_token)
    other_ref = Process.monitor(other.channel_pid)

    # The same device connects again: its old connection is closed
    join(ctx.alice_token)
    assert_receive {:DOWN, ^first_ref, :process, _, _}
    refute_received {:DOWN, ^other_ref, :process, _, _}

    connected = PhoneModem.connected(ctx.alice.id)

    assert Enum.sort(Enum.map(connected, & &1.device_id)) ==
             Enum.sort([ctx.alice_phone.id, second_phone.id])

    # A sender can pick the phone
    task = send_async(id: "picked", user_id: ctx.alice.id, device_id: second_phone.id)
    assert_push "send_sms", %{"id" => "picked"}
    push(other, "sms_result", %{"id" => "picked", "status" => "sent"})
    assert Task.await(task) == :ok
  end

  test "signing a phone out disconnects it", ctx do
    socket = join(ctx.alice_token)
    ref = Process.monitor(socket.channel_pid)

    {:ok, _} = Accounts.revoke_device(ctx.alice_phone)
    assert_receive {:DOWN, ^ref, :process, _, _}

    _ = :sys.get_state(PhoneModem)
    assert PhoneModem.status(ctx.alice.id) == :disconnected

    {:ok, socket} = connect(PhoneSocket, %{"token" => ctx.alice_token})

    assert {:error, %{reason: "invalid_token"}} =
             subscribe_and_join(socket, GatewayChannel, "gateway:phone")
  end

  test "suspending a user disconnects their phones", ctx do
    socket = join(ctx.alice_token)
    ref = Process.monitor(socket.channel_pid)

    {:ok, _} = Accounts.admin_update_user(ctx.alice, %{status: "suspended"})
    assert_receive {:DOWN, ^ref, :process, _, _}
  end

  test "a phone can only report delivery of its owner's messages", ctx do
    {:ok, alices} =
      Messages.enqueue("user:#{ctx.alice.id}", %{to: "+254712345678", body: "a"},
        user_id: ctx.alice.id
      )

    {:ok, bobs} =
      Messages.enqueue("user:#{ctx.bob.id}", %{to: "+254712345678", body: "b"},
        user_id: ctx.bob.id
      )

    alice = join(ctx.alice_token)

    ref = push(alice, "sms_delivered", %{"id" => bobs.id})
    assert_reply ref, :ok
    assert %{status: "queued"} = Messages.get(bobs.id)

    ref = push(alice, "sms_delivered", %{"id" => alices.id})
    assert_reply ref, :ok
    assert %{status: "delivered"} = Messages.get(alices.id)
  end

  test "device_info updates the phone's telemetry and last seen", ctx do
    alice = join(ctx.alice_token)

    push(alice, "device_info", %{"battery" => 80, "signal" => 3, "app_version" => "1.2.0"})
    _ = :sys.get_state(alice.channel_pid)
    _ = :sys.get_state(PhoneModem)

    assert [%{info: %{"battery" => 80}}] = PhoneModem.connected(ctx.alice.id)
    assert [%{app_version: "1.2.0"}] = Accounts.list_devices(ctx.alice.id)
  end
end
