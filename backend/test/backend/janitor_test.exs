defmodule Backend.JanitorTest do
  use Backend.DataCase, async: false

  import Ecto.Query
  alias Backend.{Janitor, Messages, Repo}
  alias Backend.Messages.Message

  @phone "+254712345678"

  test "deletes finished messages past retention, keeps recent and queued ones" do
    old = Messages.record_direct_send("public", "otp", @phone, "code")
    recent = Messages.record_direct_send("public", "otp", @phone, "code")
    {:ok, queued} = Messages.enqueue("test_system", %{to: @phone, body: "hi"})

    long_ago = DateTime.add(DateTime.utc_now(), -31 * 86_400, :second)

    Repo.update_all(
      from(m in Message, where: m.id in ^[old.id, queued.id]),
      set: [inserted_at: long_ago]
    )

    assert %{messages: 1} = Janitor.run()
    refute Messages.get(old.id)
    assert Messages.get(recent.id)
    assert Messages.get(queued.id)
  end
end
