defmodule Backend.OutboxTest do
  use Backend.DataCase, async: false

  import Backend.SmsHelpers

  alias Backend.{Messages, Outbox}
  alias Backend.Messages.Message
  alias Backend.Modem.Mock

  @phone "+254712345678"

  setup :reset_sms_state

  defp enqueue!(body \\ "Hello") do
    {:ok, message} = Messages.enqueue("test_system", %{to: @phone, body: body})
    message
  end

  test "sends queued messages one at a time, oldest first, passing the message id" do
    first = enqueue!("first")
    second = enqueue!("second")

    assert Outbox.drain() == 2

    assert [%{id: id2, body: "second"}, %{id: id1, body: "first"}] = Mock.outbox()
    assert {id1, id2} == {first.id, second.id}
    assert %Message{status: "sent"} = Messages.get(first.id)
    assert %Message{status: "sent"} = Messages.get(second.id)
  end

  test "keeps messages queued without spending attempts while the modem is offline" do
    message = enqueue!()
    Mock.set_status(:disconnected)

    assert Outbox.drain() == 1
    assert %Message{status: "queued", attempts: 0} = Messages.get(message.id)

    # Phone comes back
    Mock.set_status(:ready)
    make_due(message.id)
    assert Outbox.drain() == 1
    assert %Message{status: "sent", attempts: 1} = Messages.get(message.id)
  end

  test "retries modem errors, then marks the message failed" do
    message = enqueue!()
    Mock.set_status({:failing, :cms_error})

    for _ <- 1..3 do
      make_due(message.id)
      Outbox.drain()
    end

    assert %Message{status: "failed", attempts: 3, last_error: "cms_error"} =
             Messages.get(message.id)

    assert Mock.outbox() == []
  end

  test "pauses at the daily send limit" do
    original = Application.get_env(:backend, :daily_send_limit)
    Application.put_env(:backend, :daily_send_limit, 1)
    on_exit(fn -> Application.put_env(:backend, :daily_send_limit, original) end)

    first = enqueue!("one")
    second = enqueue!("two")

    assert Outbox.drain() == 1
    assert Outbox.daily_limit_reached?()
    refute Outbox.capacity_available?()
    assert %Message{status: "sent"} = Messages.get(first.id)
    assert %Message{status: "queued"} = Messages.get(second.id)
  end
end
