defmodule Backend.Modem.StatusTest do
  use ExUnit.Case, async: false

  alias Backend.Modem.Android

  setup do
    # Start a lightweight mock HTTP server on an ephemeral port
    {:ok, listen_socket} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(listen_socket)

    server_pid =
      spawn_link(fn ->
        mock_http_loop(listen_socket)
      end)

    Application.put_env(:backend, :android_sms_url, "http://127.0.0.1:#{port}")
    Application.put_env(:backend, :android_sms_user, "user")
    Application.put_env(:backend, :android_sms_pass, "pass")

    # Start the Android modem GenServer under a unique test name or restart it
    # Stop existing if running
    case GenServer.whereis(Android) do
      nil ->
        :ok

      pid ->
        GenServer.stop(pid, :normal, 1000)
    end

    {:ok, modem_pid} = Android.start_link()

    on_exit(fn ->
      Process.unlink(server_pid)
      Process.exit(server_pid, :kill)
      :gen_tcp.close(listen_socket)

      if Process.alive?(modem_pid) do
        GenServer.stop(modem_pid, :normal, 1000)
      end
    end)

    %{port: port}
  end

  defp mock_http_loop(listen_socket) do
    case :gen_tcp.accept(listen_socket, 5_000) do
      {:ok, client_socket} ->
        spawn(fn -> handle_http_client(client_socket) end)
        mock_http_loop(listen_socket)

      {:error, _} ->
        :ok
    end
  end

  defp handle_http_client(socket) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, data} ->
        cond do
          String.contains?(data, "GET /health") ->
            response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK"
            :gen_tcp.send(socket, response)
            :gen_tcp.close(socket)

          String.contains?(data, "POST /message") ->
            # Simulate a slow modem send of 1 second
            Process.sleep(800)
            response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK"
            :gen_tcp.send(socket, response)
            :gen_tcp.close(socket)

          true ->
            response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n"
            :gen_tcp.send(socket, response)
            :gen_tcp.close(socket)
        end

      _ ->
        :gen_tcp.close(socket)
    end
  end

  # Polls instead of sleeping a fixed time: the first HTTP request can be slow
  # while the connection pool warms up.
  defp wait_for_status(expected, timeout_ms \\ 2_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_status(expected, deadline)
  end

  defp do_wait_for_status(expected, deadline) do
    cond do
      Android.status() == expected ->
        true

      System.monotonic_time(:millisecond) > deadline ->
        false

      true ->
        Process.sleep(10)
        do_wait_for_status(expected, deadline)
    end
  end

  test "status/0 returns within 100ms (and reports :busy) while a send is in progress" do
    # Trigger health check to be ready
    send(GenServer.whereis(Android), :check_health)
    assert wait_for_status(:ready)

    # Start a send in a separate Task (takes ~800ms)
    send_task =
      Task.async(fn ->
        Android.send_sms("+254712345678", "Code: 123456")
      end)

    # Wait for the task to initiate the send and set status to :busy
    assert wait_for_status(:busy)

    # Measure status() duration while send is in progress
    {duration_us, status} = :timer.tc(fn -> Android.status() end)

    # 100ms = 100,000 microseconds
    assert duration_us < 100_000, "status/0 took #{duration_us}us, expected < 100,000us"
    assert status == :busy

    # Wait for the send task to finish
    assert Task.await(send_task, 3_000) == :ok

    # After send finishes, status returns to :ready
    assert Android.status() == :ready
  end
end
