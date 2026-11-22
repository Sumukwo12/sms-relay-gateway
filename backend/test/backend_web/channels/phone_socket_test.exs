defmodule BackendWeb.PhoneSocketTest do
  use BackendWeb.ChannelCase, async: false

  alias BackendWeb.PhoneSocket

  test "socket accepts connection with binary token and stores in assigns" do
    assert {:ok, socket} = connect(PhoneSocket, %{"token" => "some_token"})
    assert socket.assigns.token == "some_token"
    assert is_nil(PhoneSocket.id(socket))
  end

  test "socket rejects missing or non-binary token" do
    assert :error = connect(PhoneSocket, %{})
    assert :error = connect(PhoneSocket, %{"token" => nil})
    assert :error = connect(PhoneSocket, %{"token" => 12345})
  end
end
