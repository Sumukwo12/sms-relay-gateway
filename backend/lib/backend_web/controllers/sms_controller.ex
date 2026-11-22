defmodule BackendWeb.SmsController do
  @moduledoc """
  REST controller for the SMS verification API.

  Endpoints:
    POST /api/send-code         — generate & send a verification code
    POST /api/verify-code       — verify a submitted code
    GET  /api/modem/status      — current modem status
    GET  /api/rate-limit/:phone — rate limit info for a phone number
  """

  use BackendWeb, :controller

  alias Backend.SmsGateway

  require Logger

  # POST /api/send-code
  # Body: { "phone": "+254712345678" }
  def send_code(conn, %{"phone" => phone}) when is_binary(phone) do
    client_ip = get_client_ip(conn)

    case SmsGateway.send_verification_code(phone, client_ip: client_ip) do
      {:ok, :sent} ->
        json(conn, %{
          success: true,
          message: "Verification code sent successfully.",
          has_pending: true,
          expires_in_seconds: SmsGateway.code_ttl_seconds()
        })

      {:error, :invalid_phone} ->
        error(
          conn,
          :unprocessable_entity,
          "invalid_phone",
          "Phone number must be in E.164 format (e.g. +254712345678)."
        )

      {:error, :rate_limited, retry_after} ->
        error(
          conn,
          :too_many_requests,
          "rate_limited",
          "Too many attempts. Try again in #{ceil(retry_after / 60)} minute(s).",
          %{retry_after_seconds: retry_after}
        )

      {:error, :daily_limit_reached} ->
        error(
          conn,
          :too_many_requests,
          "daily_limit_reached",
          "The daily SMS limit has been reached. Try again later."
        )

      {:error, :modem_disconnected} ->
        error(
          conn,
          :service_unavailable,
          "modem_disconnected",
          "SMS modem is not connected. Please check the hardware."
        )

      {:error, :modem_busy} ->
        error(
          conn,
          :service_unavailable,
          "modem_busy",
          "Modem is busy. Please retry in a moment."
        )

      {:error, :modem_error, reason} ->
        Logger.error("[SmsController] Modem error: #{inspect(reason)}")
        error(conn, :bad_gateway, "modem_error", "Failed to send SMS.")
    end
  end

  def send_code(conn, _params) do
    error(conn, :bad_request, "missing_phone", "Request body must include a 'phone' field.")
  end

  # POST /api/verify-code
  # Body: { "phone": "+254712345678", "code": "483921" }
  def verify_code(conn, %{"phone" => phone, "code" => code})
      when is_binary(phone) and is_binary(code) do
    case SmsGateway.verify_code(phone, code) do
      :ok ->
        json(conn, %{
          success: true,
          verified: true,
          message: "Phone number verified successfully."
        })

      {:error, :invalid_code} ->
        verify_error(
          conn,
          :unprocessable_entity,
          "invalid_code",
          "The code you entered is incorrect."
        )

      {:error, :too_many_attempts} ->
        verify_error(
          conn,
          :too_many_requests,
          "too_many_attempts",
          "Too many incorrect attempts. Please request a new code."
        )

      {:error, :expired_or_missing} ->
        verify_error(
          conn,
          :unprocessable_entity,
          "expired_or_missing",
          "No active code found. Please request a new one."
        )

      {:error, :cache_error} ->
        verify_error(
          conn,
          :internal_server_error,
          "server_error",
          "Could not verify the code right now. Please try again."
        )
    end
  end

  def verify_code(conn, _params) do
    error(
      conn,
      :bad_request,
      "missing_params",
      "Request body must include 'phone' and 'code' fields."
    )
  end

  # GET /api/modem/status
  def modem_status(conn, _params) do
    status = SmsGateway.modem_status()
    json(conn, %{status: status, ready: status == :ready})
  end

  # GET /api/rate-limit/:phone
  def rate_limit_info(conn, %{"phone" => phone}) do
    case SmsGateway.rate_limit_info(phone) do
      {:ok, info} ->
        json(conn, info)

      {:error, :invalid_phone} ->
        error(
          conn,
          :unprocessable_entity,
          "invalid_phone",
          "Phone number must be in E.164 format (e.g. +254712345678)."
        )
    end
  end

  defp verify_error(conn, status, code, message),
    do: error(conn, status, code, message, %{verified: false})

  defp error(conn, status, code, message, extra \\ %{}) do
    conn
    |> put_status(status)
    |> json(Map.merge(%{success: false, error: code, message: message}, extra))
  end

  defp get_client_ip(conn) do
    trust_proxy = Application.get_env(:backend, :trust_proxy, false)

    if trust_proxy do
      case get_req_header(conn, "x-forwarded-for") do
        [header | _] ->
          header
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> List.last() || format_ip(conn.remote_ip)

        [] ->
          format_ip(conn.remote_ip)
      end
    else
      format_ip(conn.remote_ip)
    end
  end

  defp format_ip(ip) when is_tuple(ip) do
    ip |> :inet.ntoa() |> to_string()
  end

  defp format_ip(ip) when is_binary(ip), do: ip
  defp format_ip(_), do: "unknown"
end
