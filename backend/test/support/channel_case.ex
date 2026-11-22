defmodule BackendWeb.ChannelCase do
  @moduledoc """
  This module defines the test case to be used by
  channel tests.

  Such tests rely on `Phoenix.ChannelTest` and also
  import other functionality for testing channels.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint BackendWeb.Endpoint

      import Phoenix.ChannelTest
      import BackendWeb.ChannelCase
    end
  end

  setup tags do
    Backend.DataCase.setup_sandbox(tags)
    :ok
  end
end
