defmodule Backend.DataCase do
  @moduledoc """
  Test case for code that touches the database (the message outbox).

  The sandbox runs in shared mode so the global `Backend.Outbox` process and
  channel processes can use the test's connection. Tests that use it must not
  be async.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Backend.Repo
      import Backend.DataCase
    end
  end

  setup tags do
    setup_sandbox(tags)
    :ok
  end

  @doc "Check out a sandbox connection shared with every process in the test."
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Backend.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end
end
