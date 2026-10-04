if Code.ensure_loaded?(Circuits.UART) do
  defmodule Backend.Modem.UART do
    @moduledoc """
    GenServer that owns the serial connection to the USB GSM modem.

    Communicates via AT commands over Circuits.UART (serial port).
    All SMS sends are serialised through this process to prevent
    concurrent write conflicts on the serial line. If the port cannot
    be opened (or disappears), it retries every few seconds.

    ## AT Command flow

      1. AT+CMGF=1          → set text mode
      2. AT+CMGS="<num>"\\r  → target number; modem replies with ">"
      3. <message>          → body text
      4. <<26>>             → Ctrl+Z signals end-of-message
      5. Modem replies      → +CMGS: <ref>  OR  +CMS ERROR: <code>

    ## Config keys
      - :modem_port   — e.g. "COM3" (Windows) or "/dev/ttyUSB0" (Linux)
      - :modem_baud   — usually 9600 or 115200
    """

    use GenServer
    require Logger

    alias Circuits.UART

    @behaviour Backend.Modem

    @ctrl_z <<26>>
    @esc <<27>>
    # ms budget for initialising the modem
    @init_timeout 8_000
    # ms budget for the full send sequence (network ack can be slow)
    @send_timeout 30_000
    # ms between reconnect attempts while disconnected
    @reconnect_interval 10_000
    # read errors that mean the device went away
    @fatal_errors [:ebadf, :eio, :enxio, :enoent]

    # ── Public API ──────────────────────────────────────────────────────────

    @impl Backend.Modem
    def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

    @impl Backend.Modem
    def send_sms(phone_number, message) do
      GenServer.call(__MODULE__, {:send_sms, phone_number, message}, @send_timeout + 5_000)
    end

    @impl Backend.Modem
    def status, do: GenServer.call(__MODULE__, :status)

    # ── GenServer callbacks ─────────────────────────────────────────────────

    @impl true
    def init(_) do
      {:ok, uart} = UART.start_link()

      state = %{
        uart: uart,
        port: Application.get_env(:backend, :modem_port, "COM3"),
        baud: Application.get_env(:backend, :modem_baud, 9600),
        status: :disconnected
      }

      {:ok, state, {:continue, :connect}}
    end

    @impl true
    def handle_continue(:connect, state), do: {:noreply, connect(state)}

    @impl true
    def handle_info(:reconnect, %{status: :disconnected} = state), do: {:noreply, connect(state)}
    def handle_info(:reconnect, state), do: {:noreply, state}

    @impl true
    def handle_call(:status, _from, state), do: {:reply, state.status, state}

    def handle_call({:send_sms, _, _}, _from, %{status: :disconnected} = state),
      do: {:reply, {:error, :modem_disconnected}, state}

    def handle_call({:send_sms, phone, message}, _from, state) do
      case do_send(state.uart, phone, message) do
        :ok ->
          Logger.info("[Modem] SMS sent to #{phone}")
          {:reply, :ok, state}

        {:error, reason} when reason in @fatal_errors ->
          Logger.error(
            "[Modem] Lost #{state.port} (#{inspect(reason)}) while sending to #{phone}"
          )

          {:reply, {:error, :modem_disconnected}, disconnect(state)}

        {:error, reason} = err ->
          Logger.error("[Modem] Send to #{phone} failed: #{inspect(reason)}")
          {:reply, err, state}
      end
    end

    # ── Connection management ───────────────────────────────────────────────

    defp connect(state) do
      with :ok <- UART.open(state.uart, state.port, speed: state.baud, active: false),
           :ok <- init_modem(state.uart) do
        Logger.info("[Modem] Ready on #{state.port} @ #{state.baud} baud (SMS text mode)")
        %{state | status: :ready}
      else
        {:error, reason} ->
          Logger.error(
            "[Modem] #{state.port} unavailable: #{inspect(reason)}; " <>
              "retrying in #{div(@reconnect_interval, 1000)}s"
          )

          disconnect(state)
      end
    end

    defp disconnect(state) do
      UART.close(state.uart)
      Process.send_after(self(), :reconnect, @reconnect_interval)
      %{state | status: :disconnected}
    end

    defp init_modem(uart) do
      deadline = deadline(@init_timeout)

      with :ok <- UART.flush(uart, :receive),
           :ok <- command(uart, "AT", deadline),
           # Disable command echo so replies are easier to parse
           :ok <- command(uart, "ATE0", deadline) do
        command(uart, "AT+CMGF=1", deadline)
      end
    end

    # ── Sending ─────────────────────────────────────────────────────────────

    defp do_send(uart, phone, message) do
      deadline = deadline(@send_timeout)

      with :ok <- UART.flush(uart, :receive),
           :ok <- command(uart, "AT+CMGF=1", deadline),
           :ok <- UART.write(uart, ~s(AT+CMGS="#{phone}"\r)),
           {:ok, _} <- read_until(uart, deadline, &parse_prompt/1),
           :ok <- UART.write(uart, message <> @ctrl_z),
           {:ok, ref} <- read_until(uart, deadline, &parse_cmgs/1) do
        Logger.debug("[Modem] +CMGS ref=#{ref}")
        :ok
      else
        {:error, :timeout} ->
          # Abort any half-entered message so the modem accepts new commands
          UART.write(uart, @esc)
          {:error, :send_timeout}

        {:error, _} = err ->
          err
      end
    end

    # ── AT helpers ──────────────────────────────────────────────────────────

    defp command(uart, cmd, deadline) do
      Logger.debug("[Modem] TX #{inspect(cmd)}")

      with :ok <- UART.write(uart, cmd <> "\r"),
           {:ok, _} <- read_until(uart, deadline, &parse_ok/1) do
        :ok
      end
    end

    # Accumulate modem output until `parse` returns something other than
    # :more, or the deadline passes. Replies can arrive split across reads.
    defp read_until(uart, deadline, parse, buffer \\ "") do
      remaining = deadline - System.monotonic_time(:millisecond)

      if remaining <= 0 do
        {:error, :timeout}
      else
        case UART.read(uart, remaining) do
          # Circuits.UART returns an empty binary on timeout
          {:ok, ""} ->
            {:error, :timeout}

          {:ok, data} when is_binary(data) ->
            buffer = buffer <> data
            Logger.debug("[Modem] RX #{inspect(buffer)}")

            case parse.(buffer) do
              :more -> read_until(uart, deadline, parse, buffer)
              result -> result
            end

          {:error, _} = err ->
            err
        end
      end
    end

    defp parse_ok(buf) do
      cond do
        String.contains?(buf, "OK") -> {:ok, buf}
        error = at_error(buf) -> error
        true -> :more
      end
    end

    defp parse_prompt(buf) do
      cond do
        String.contains?(buf, ">") -> {:ok, buf}
        error = at_error(buf) -> error
        true -> :more
      end
    end

    defp parse_cmgs(buf) do
      cond do
        match = Regex.run(~r/\+CMGS:\s*(\d+)/, buf, capture: :all_but_first) ->
          {:ok, hd(match)}

        error = at_error(buf) ->
          error

        true ->
          :more
      end
    end

    defp at_error(buf) do
      cond do
        match = Regex.run(~r/\+CMS ERROR:\s*(\w+)/, buf, capture: :all_but_first) ->
          {:error, {:cms_error, hd(match)}}

        match = Regex.run(~r/\+CME ERROR:\s*(\w+)/, buf, capture: :all_but_first) ->
          {:error, {:cme_error, hd(match)}}

        String.contains?(buf, "ERROR") ->
          {:error, :at_error}

        true ->
          nil
      end
    end

    defp deadline(timeout_ms), do: System.monotonic_time(:millisecond) + timeout_ms
  end
end
