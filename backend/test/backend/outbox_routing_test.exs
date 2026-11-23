defmodule Backend.OutboxRoutingTest do
  @moduledoc "Which queued messages the outbox may pick while phones and limits vary."
  use Backend.DataCase, async: false

  import Backend.AccountHelpers
  import Backend.SmsHelpers

  alias Backend.{Accounts, Messages, Outbox}
  alias Backend.Modem.Mock

  @phone "+254712345678"

  setup :reset_sms_state

  defp enqueue!(user, body) do
    client = if user, do: "user:#{user.id}", else: "test_system"
    {:ok, m} = Messages.enqueue(client, %{to: @phone, body: body}, user_id: user && user.id)
    m
  end

  defp routing(owners, opts \\ []) do
    %{
      owners: owners,
      blocked: Keyword.get(opts, :blocked, []),
      system_ok: Keyword.get(opts, :system_ok, true)
    }
  end

  test "only messages of owners with a phone online are picked" do
    alice = user_fixture(status: "approved")
    bob = user_fixture(status: "approved")
    _system = enqueue!(nil, "system")
    _alices = enqueue!(alice, "alice")
    bobs = enqueue!(bob, "bob")

    only_bob = routing(%{users: MapSet.new([bob.id]), system: false})
    assert %{id: id} = Messages.checkout_next(only_bob)
    assert id == bobs.id
    assert Messages.checkout_next(only_bob) == nil
  end

  test "blocked users and the server-level cap are respected" do
    alice = user_fixture(status: "approved")
    enqueue!(nil, "system")
    enqueue!(alice, "alice")

    assert Messages.checkout_next(routing(:any, blocked: [alice.id], system_ok: false)) == nil
    assert %{body: "alice"} = Messages.checkout_next(routing(:any, system_ok: false))
  end

  test "the outbox keeps sending other users' messages when one can't send" do
    pending = user_fixture()
    approved = user_fixture(status: "approved")
    held = enqueue!(pending, "held")
    sent = enqueue!(approved, "sent")

    assert Outbox.drain() == 1
    assert %{status: "queued", attempts: 0} = Messages.get(held.id)
    assert %{status: "sent"} = Messages.get(sent.id)
    assert [%{body: "sent"}] = Mock.outbox()

    {:ok, _} = Accounts.admin_update_user(pending, %{status: "approved"})
    assert Outbox.drain() == 1
    assert %{status: "sent"} = Messages.get(held.id)
  end

  test "a user over their daily limit waits; others don't" do
    limited = user_fixture(status: "approved")
    {:ok, limited} = Accounts.admin_update_user(limited, %{daily_limit: 1})
    enqueue!(limited, "one")
    enqueue!(limited, "two")
    enqueue!(nil, "system")

    assert Outbox.drain() == 2
    assert Enum.sort(Enum.map(Mock.outbox(), & &1.body)) == ["one", "system"]
    assert Messages.queue_depth(limited.id) == 1
    refute Outbox.capacity_available?(1, limited)
  end
end
