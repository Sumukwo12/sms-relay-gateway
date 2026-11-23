defmodule BackendWeb.AccountController do
  @moduledoc """
  The signed-in user's dashboard API (session cookie).

    GET    /api/account                  overview: user, usage, phones, webhook secret
    POST   /api/account/password         {current_password, new_password}
    POST   /api/account/webhook-secret   rotate the webhook signing secret
    GET    /api/account/devices          linked phones
    PATCH  /api/account/devices/:id      {name}
    DELETE /api/account/devices/:id      sign the phone out
    GET    /api/account/api-keys
    POST   /api/account/api-keys         {name} → the key, shown once
    DELETE /api/account/api-keys/:id
    GET    /api/account/messages         latest 100 messages
    POST   /api/account/console/sms      {to, body, device_id?}  test send
    POST   /api/account/console/otp/send   {phone, device_id?}
    POST   /api/account/console/otp/verify {phone, code}
  """

  use BackendWeb, :controller

  alias Backend.{Accounts, Messages, Modem, SmsGateway}
  alias Backend.Accounts.User
  alias BackendWeb.AccountJSON

  def show(conn, _params) do
    user = conn.assigns.current_user

    json(conn, %{
      success: true,
      user: AccountJSON.user(user),
      webhook_secret: user.webhook_secret,
      usage: %{
        sent_last_24h: Messages.sent_last_24h(user.id),
        queued: Messages.queue_depth(user.id),
        daily_limit: Accounts.daily_limit(user)
      },
      gateway_online: Modem.status(user.id) == :ready,
      devices: AccountJSON.devices(user.id),
      api_keys: length(Accounts.list_api_keys(user.id))
    })
  end

  def change_password(conn, params) do
    case Accounts.change_password(
           conn.assigns.current_user,
           params["current_password"],
           params["new_password"]
         ) do
      :ok -> json(conn, %{success: true})
      {:error, errors} -> AccountJSON.errors_response(conn, errors)
    end
  end

  def rotate_webhook_secret(conn, _params) do
    user = Accounts.rotate_webhook_secret(conn.assigns.current_user)
    json(conn, %{success: true, webhook_secret: user.webhook_secret})
  end

  # ── Phones ──────────────────────────────────────────────────────────────────

  def devices(conn, _params) do
    json(conn, %{success: true, devices: AccountJSON.devices(conn.assigns.current_user.id)})
  end

  def update_device(conn, %{"id" => id} = params) do
    with %Backend.Accounts.Device{} = device <- find_device(conn, id) do
      case Accounts.rename_device(device, params["name"]) do
        {:ok, device} -> json(conn, %{success: true, device: AccountJSON.device(device)})
        {:error, errors} -> AccountJSON.errors_response(conn, errors)
      end
    end
  end

  def delete_device(conn, %{"id" => id}) do
    with %Backend.Accounts.Device{} = device <- find_device(conn, id) do
      {:ok, _} = Accounts.revoke_device(device)
      json(conn, %{success: true})
    end
  end

  defp find_device(conn, id) do
    Accounts.get_device(conn.assigns.current_user.id, id) ||
      AccountJSON.error(conn, :not_found, "not_found", "No such phone.")
  end

  # ── API keys ────────────────────────────────────────────────────────────────

  def api_keys(conn, _params) do
    keys = Accounts.list_api_keys(conn.assigns.current_user.id)
    json(conn, %{success: true, api_keys: Enum.map(keys, &AccountJSON.api_key/1)})
  end

  def create_api_key(conn, params) do
    case Accounts.create_api_key(conn.assigns.current_user, params["name"]) do
      {:ok, api_key, key} ->
        conn
        |> put_status(:created)
        |> json(%{success: true, api_key: AccountJSON.api_key(api_key), key: key})

      {:error, errors} ->
        AccountJSON.errors_response(conn, errors)
    end
  end

  def delete_api_key(conn, %{"id" => id}) do
    case Accounts.revoke_api_key(conn.assigns.current_user.id, id) do
      :ok -> json(conn, %{success: true})
      {:error, :not_found} -> AccountJSON.error(conn, :not_found, "not_found", "No such key.")
    end
  end

  # ── Messages and test console ───────────────────────────────────────────────

  def messages(conn, _params) do
    messages = Messages.list_for_user(conn.assigns.current_user.id)
    json(conn, %{success: true, messages: Enum.map(messages, &AccountJSON.message/1)})
  end

  def console_sms(conn, params) do
    user = conn.assigns.current_user

    with :ok <- can_send(conn, user),
         {:ok, device_id} <- device_param(conn, params) do
      attrs = Map.take(params, ["to", "body"])
      opts = [user: user, device_id: device_id]

      case SmsGateway.queue_message(User.client(user), attrs, opts) do
        {:ok, message} ->
          conn
          |> put_status(:accepted)
          |> json(%{success: true, message: AccountJSON.message(message)})

        {:error, :daily_limit_reached} ->
          daily_limit(conn)

        {:error, {:invalid, field, reason}} ->
          AccountJSON.errors_response(conn, %{field => reason})
      end
    end
  end

  def console_otp_send(conn, params) do
    user = conn.assigns.current_user

    with :ok <- can_send(conn, user),
         {:ok, device_id} <- device_param(conn, params) do
      opts = [user: user, device_id: device_id]

      case SmsGateway.queue_verification_code(params["phone"] || "", User.client(user), opts) do
        {:ok, message} ->
          conn
          |> put_status(:accepted)
          |> json(%{
            success: true,
            message: AccountJSON.message(message),
            expires_in_seconds: SmsGateway.code_ttl_seconds()
          })

        {:error, :invalid_phone} ->
          AccountJSON.errors_response(conn, %{
            phone: "must be an E.164 phone number, e.g. +254712345678"
          })

        {:error, {:invalid, field, reason}} ->
          AccountJSON.errors_response(conn, %{field => reason})

        {:error, :rate_limited, retry_after} ->
          conn
          |> put_status(:too_many_requests)
          |> json(%{
            success: false,
            error: "rate_limited",
            message:
              "Too many codes sent to this number. Try again in #{ceil(retry_after / 60)} minute(s).",
            retry_after_seconds: retry_after
          })

        {:error, :daily_limit_reached} ->
          daily_limit(conn)
      end
    end
  end

  def console_otp_verify(conn, %{"phone" => phone, "code" => code})
      when is_binary(phone) and is_binary(code) do
    client = User.client(conn.assigns.current_user)

    case SmsGateway.verify_code(phone, code, client) do
      :ok ->
        json(conn, %{success: true, verified: true})

      {:error, reason} ->
        {status, message} =
          case reason do
            :invalid_code ->
              {:unprocessable_entity, "The code is incorrect."}

            :too_many_attempts ->
              {:too_many_requests, "Too many incorrect attempts; send a new code."}

            :expired_or_missing ->
              {:unprocessable_entity, "No active code for this number."}

            _ ->
              {:internal_server_error, "Could not verify the code right now."}
          end

        conn
        |> put_status(status)
        |> json(%{success: false, verified: false, error: to_string(reason), message: message})
    end
  end

  def console_otp_verify(conn, _params),
    do: AccountJSON.errors_response(conn, %{code: "and phone are required"})

  defp can_send(conn, user) do
    if Accounts.can_send?(user),
      do: :ok,
      else:
        AccountJSON.error(
          conn,
          :forbidden,
          "account_pending",
          "Your account is waiting for an administrator's approval before it can send SMS."
        )
  end

  defp device_param(conn, params) do
    case params["device_id"] do
      empty when empty in [nil, ""] ->
        {:ok, nil}

      id ->
        case Accounts.get_device(conn.assigns.current_user.id, id) do
          nil ->
            AccountJSON.errors_response(conn, %{device_id: "is not one of your linked phones"})

          device ->
            {:ok, device.id}
        end
    end
  end

  defp daily_limit(conn) do
    AccountJSON.error(
      conn,
      :too_many_requests,
      "daily_limit_reached",
      "You have reached your daily SMS limit. Try again later."
    )
  end
end
