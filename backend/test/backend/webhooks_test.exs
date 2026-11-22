defmodule Backend.WebhooksTest do
  use Backend.DataCase, async: false

  import Ecto.Query
  alias Backend.{Messages, Repo, Webhooks}
  alias Backend.Webhooks.Delivery

  @phone "+254712345678"

  setup {Req.Test, :set_req_test_to_shared}

  defp sent_message do
    {:ok, message} =
      Messages.enqueue("test_system", %{
        to: @phone,
        body: "hi",
        callback_url: "https://example.test/hook"
      })

    Messages.checkout_next()
    {:ok, sent} = Messages.mark_sent(message.id)
    sent
  end

  defp make_due do
    Repo.update_all(Delivery,
      set: [next_attempt_at: DateTime.add(DateTime.utc_now(), -1, :second)]
    )
  end

  # Responds with the given statuses in turn, reporting each event to the test
  defp stub_responses(statuses) do
    test_pid = self()
    {:ok, agent} = Agent.start_link(fn -> statuses end)

    Req.Test.stub(Webhooks, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:webhook, Jason.decode!(raw)["event"]})

      status =
        Agent.get_and_update(agent, fn
          [status] -> {status, [status]}
          [status | rest] -> {status, rest}
        end)

      conn |> Plug.Conn.put_status(status) |> Req.Test.json(%{})
    end)
  end

  test "deliveries are stored and retried until the receiver accepts them" do
    stub_responses([500, 200])
    message = sent_message()

    assert Webhooks.drain() == 1
    assert_received {:webhook, "message.sent"}

    assert [%Delivery{status: "pending", attempts: 1, last_error: "callback returned HTTP 500"}] =
             Repo.all(Delivery)

    # Not due yet: backoff
    assert Webhooks.drain() == 0

    make_due()
    assert Webhooks.drain() == 1
    assert [%Delivery{status: "delivered", attempts: 2, message_id: id}] = Repo.all(Delivery)
    assert id == message.id
    assert Webhooks.pending_count() == 0
  end

  test "a 4xx answer is final" do
    stub_responses([404])
    sent_message()

    Webhooks.drain()
    assert [%Delivery{status: "failed", attempts: 1}] = Repo.all(Delivery)
  end

  test "gives up after the configured number of attempts" do
    Application.put_env(:backend, :webhook_max_attempts, 2)
    on_exit(fn -> Application.put_env(:backend, :webhook_max_attempts, 12) end)
    stub_responses([503])
    sent_message()

    Webhooks.drain()
    make_due()
    Webhooks.drain()
    assert [%Delivery{status: "failed", attempts: 2}] = Repo.all(Delivery)
  end

  test "events for one message are delivered in order" do
    stub_responses([500, 200])
    message = sent_message()
    {:ok, _} = Messages.mark_delivered(message.id)

    # Only the first event is tried while it is pending
    assert Webhooks.drain() == 1
    assert_received {:webhook, "message.sent"}
    refute_received {:webhook, "message.delivered"}

    make_due()
    Webhooks.drain()
    assert_received {:webhook, "message.sent"}

    Webhooks.drain()
    assert_received {:webhook, "message.delivered"}

    assert ["delivered", "delivered"] =
             Repo.all(from(d in Delivery, order_by: d.id, select: d.status))
  end
end
