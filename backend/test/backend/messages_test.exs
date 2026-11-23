defmodule Backend.MessagesTest do
  use Backend.DataCase, async: false

  alias Backend.Messages
  alias Backend.Messages.Message

  @phone "+254712345678"

  defp enqueue!(attrs \\ %{}, opts \\ []) do
    {:ok, message} =
      Messages.enqueue("test_system", Map.merge(%{to: @phone, body: "Hello"}, attrs), opts)

    message
  end

  describe "enqueue/3" do
    test "queues a valid message with a normalized number" do
      message = enqueue!(%{to: "+254 712-345 678", reference: "order-42"})

      assert %Message{status: "queued", attempts: 0, to: @phone, kind: "notification"} = message
      assert message.reference == "order-42"
      assert "msg_" <> _ = message.id
      assert Messages.queue_depth() == 1
    end

    test "accepts string keys" do
      assert {:ok, _} = Messages.enqueue("test_system", %{"to" => @phone, "body" => "Hi"})
    end

    test "rejects invalid fields" do
      assert {:error, :to, _} = Messages.enqueue("c", %{to: "07123", body: "Hi"})
      assert {:error, :body, _} = Messages.enqueue("c", %{to: @phone, body: "   "})
      assert {:error, :body, _} = Messages.enqueue("c", %{to: @phone})

      assert {:error, :body, _} =
               Messages.enqueue("c", %{to: @phone, body: String.duplicate("a", 481)})

      assert {:error, :callback_url, _} =
               Messages.enqueue("c", %{to: @phone, body: "Hi", callback_url: "ftp://x"})

      assert {:error, :reference, _} =
               Messages.enqueue("c", %{
                 to: @phone,
                 body: "Hi",
                 reference: String.duplicate("r", 101)
               })

      assert Messages.queue_depth() == 0
    end
  end

  test "get_for_client/2 only returns the caller's own messages" do
    message = enqueue!()
    assert Messages.get_for_client("test_system", message.id)
    refute Messages.get_for_client("other_system", message.id)
  end

  describe "lifecycle" do
    test "checkout → sent → delivered" do
      message = enqueue!()

      assert %Message{status: "sending", attempts: 1} = Messages.checkout_next()
      assert Messages.checkout_next() == nil

      assert {:ok, %Message{status: "sent", sent_at: %DateTime{}}} =
               Messages.mark_sent(message.id)

      assert {:ok, %Message{status: "delivered", delivered_at: %DateTime{}}} =
               Messages.mark_delivered(message.id)

      assert Messages.sent_last_24h() == 1
    end

    test "a failed attempt is retried later, then fails when attempts run out" do
      message = enqueue!()

      for attempt <- 1..2 do
        Backend.SmsHelpers.make_due(message.id)
        checked_out = Messages.checkout_next()
        assert checked_out.attempts == attempt

        assert {:ok, %Message{status: "queued", last_error: "boom"} = queued} =
                 Messages.attempt_failed(checked_out, "boom")

        assert DateTime.compare(queued.next_attempt_at, DateTime.utc_now()) == :gt
        assert Messages.checkout_next() == nil
      end

      Backend.SmsHelpers.make_due(message.id)
      last = Messages.checkout_next()

      assert {:ok, %Message{status: "failed", failed_at: %DateTime{}}} =
               Messages.attempt_failed(last, :boom)
    end

    test "defer/3 returns the message to the queue without spending an attempt" do
      enqueue!()
      checked_out = Messages.checkout_next()

      assert {:ok, %Message{status: "queued", attempts: 0, last_error: "modem_disconnected"}} =
               Messages.defer(checked_out, :modem_disconnected, 10)
    end

    test "a late 'sent' report rescues a message that was failed by timeout" do
      message = enqueue!()
      Messages.checkout_next()
      {:ok, _} = Messages.fail(message.id, :send_timeout)

      assert {:ok, %Message{status: "sent", last_error: nil}} =
               Messages.apply_phone_result(message.id, "sent", nil)

      assert Messages.apply_phone_result(message.id, "failed", "x") == :ignored
    end

    test "the same transition only applies once" do
      message = enqueue!()
      Messages.checkout_next()

      assert {:ok, _} = Messages.mark_sent(message.id)
      assert {:error, {:invalid_transition, "sent"}} = Messages.mark_sent(message.id)
    end

    test "OTP bodies are redacted once the message is done" do
      message = enqueue!(%{body: "Your code is 123456"}, kind: "otp")
      Messages.checkout_next()

      {:ok, sent} = Messages.mark_sent(message.id)
      assert sent.body == "[redacted]"
    end
  end

  describe "SMS parts and idempotency" do
    test "records how many SMS parts the body needs" do
      assert enqueue!(%{body: String.duplicate("a", 161)}).segments == 2
      assert enqueue!(%{body: "Habari 👋"}).segments == 1
    end

    test "rejects bodies longer than the configured number of parts" do
      # 300 non-Latin characters are 5 UCS-2 parts, over the default 4
      assert {:error, :body, reason} =
               Messages.enqueue("c", %{to: @phone, body: String.duplicate("ж", 300)})

      assert reason =~ "4 SMS parts"
    end

    test "the daily count is in SMS parts" do
      message = enqueue!(%{body: String.duplicate("a", 200)})
      Messages.checkout_next()
      Messages.mark_sent(message.id)

      assert Messages.sent_last_24h() == 2
    end

    test "notification bodies are erased once sent too" do
      message = enqueue!()
      Messages.checkout_next()

      assert {:ok, %Message{body: "[redacted]"}} = Messages.mark_sent(message.id)
    end

    test "the same idempotency key returns the original message" do
      first = enqueue!(%{}, idempotency_key: "order-7-shipped")

      assert {:existing, %Message{id: id}} =
               Messages.enqueue("test_system", %{to: @phone, body: "Hello"},
                 idempotency_key: "order-7-shipped"
               )

      assert id == first.id
      assert Messages.queue_depth() == 1

      # Keys are per system
      assert {:ok, _} =
               Messages.enqueue("other_system", %{to: @phone, body: "Hello"},
                 idempotency_key: "order-7-shipped"
               )
    end
  end

  test "expire_stale/0 fails messages whose time in the queue ran out" do
    expired = enqueue!(%{}, ttl_seconds: -1)
    fresh = enqueue!()

    assert Messages.expire_stale() == 1
    assert %Message{status: "failed", last_error: "expired"} = Messages.get(expired.id)
    assert %Message{status: "queued"} = Messages.get(fresh.id)
  end

  test "requeue_interrupted/0 puts messages stuck in sending back in the queue" do
    message = enqueue!()
    Messages.checkout_next()

    assert Messages.requeue_interrupted() == 1
    assert %Message{status: "queued"} = Messages.get(message.id)
  end
end
