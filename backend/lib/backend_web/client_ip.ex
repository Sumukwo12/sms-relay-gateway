defmodule BackendWeb.ClientIp do
  @moduledoc """
  The client's IP address. Behind a reverse proxy (`TRUST_PROXY=true`) it is
  the last address the proxy appended to `X-Forwarded-For`.
  """

  import Plug.Conn

  def get(conn) do
    if Application.get_env(:backend, :trust_proxy, false) do
      case get_req_header(conn, "x-forwarded-for") do
        [header | _] ->
          header
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> List.last() || format(conn.remote_ip)

        [] ->
          format(conn.remote_ip)
      end
    else
      format(conn.remote_ip)
    end
  end

  defp format(ip) when is_tuple(ip), do: ip |> :inet.ntoa() |> to_string()
  defp format(ip) when is_binary(ip), do: ip
  defp format(_), do: "unknown"
end
