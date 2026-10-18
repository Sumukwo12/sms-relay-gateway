defmodule BackendWeb.V1.OtpController do
  @moduledoc """
  Verification codes for integrated systems.

    POST /v1/otp/send    — {phone, reference?, callback_url?}; the gateway
                           generates the code and queues the SMS
    POST /v1/otp/verify  — {phone, code}
  """

  use BackendWeb, :controller

  alias Backend.{Messages, SmsGateway}
  alias BackendWeb.V1.Errors

  def send_code(conn, %{"phone" => phone} = params) when is_binary(phone) do
    opts = [reference: params["reference"], callback_url: params["callback_url"]]

    case SmsGateway.queue_verification_code(phone, conn.assigns.api_client, opts) do
      {:ok, message} ->
        conn
        |> put_status(:accepted)
        |> json(%{
          success: true,
          message: Messages.to_public(message),
          expires_in_seconds: SmsGateway.code_ttl_seconds()
        })

      {:error, :invalid_phone} ->
        Errors.invalid(conn, :phone, "must be an E.164 phone number, e.g. +254712345678")

      {:error, {:invalid, field, reason}} ->
        Errors.invalid(conn, field, reason)

      {:error, :rate_limited, retry_after} ->
        Errors.error(
          conn,
          :too_many_requests,
          "rate_limited",
          "Too many codes sent to this number.",
          %{
            retry_after_seconds: retry_after
          }
        )

      {:error, :daily_limit_reached} ->
        Errors.daily_limit(conn)
    end
  end

  def send_code(conn, _params), do: Errors.invalid(conn, :phone, "is required")

  def verify(conn, %{"phone" => phone, "code" => code})
      when is_binary(phone) and is_binary(code) do
    case SmsGateway.verify_code(phone, code) do
      :ok ->
        json(conn, %{success: true, verified: true})

      {:error, :invalid_code} ->
        verify_error(conn, :unprocessable_entity, "invalid_code", "The code is incorrect.")

      {:error, :too_many_attempts} ->
        verify_error(
          conn,
          :too_many_requests,
          "too_many_attempts",
          "Too many incorrect attempts; request a new code."
        )

      {:error, :expired_or_missing} ->
        verify_error(
          conn,
          :unprocessable_entity,
          "expired_or_missing",
          "No active code for this number."
        )

      {:error, :cache_error} ->
        verify_error(
          conn,
          :internal_server_error,
          "server_error",
          "Could not verify the code right now."
        )
    end
  end

  def verify(conn, _params), do: Errors.invalid(conn, :code, "phone and code are required")

  defp verify_error(conn, status, code, message),
    do: Errors.error(conn, status, code, message, %{verified: false})
end
