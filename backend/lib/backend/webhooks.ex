defmodule Backend.Webhooks do
  @moduledoc """
  Status callbacks to integrated systems.

  When a message has a `callback_url`, every status change to `sent`,
  `delivered` or `failed` is POSTed there as JSON:

      {"event": "message.delivered", "message": {...same shape as GET /v1/messages/:id...}}

  The request carries `X-Signature: sha256=<hex>`, an HMAC-SHA256 of the raw
  body keyed with the sending system's API key, so the receiver can check it
  came from this gateway. Delivery runs in the background and is retried a
  few times on network errors and 5xx responses.
  """

  require Logger

  alias Backend.{ApiKeys, Messages}
  alias Backend.Messages.Message

  @events %{
    "sent" => "message.sent",
    "delivered" => "message.delivered",
    "failed" => "message.failed"
  }

  @doc "Fire the webhook for the message's current status, if it has one."
  @spec notify(Message.t()) :: :ok
  def notify(%Message{callback_url: url, status: status} = message)
      when is_binary(url) and is_map_key(@events, status) do
    payload = Jason.encode!(%{event: @events[status], message: Messages.to_public(message)})
    secret = ApiKeys.key_for(message.client)

    Task.Supervisor.start_child(Backend.TaskSupervisor, fn ->
      deliver(url, payload, secret, message.id)
    end)

    :ok
  end

  def notify(_message), do: :ok

  @doc "The signature header value for `body` signed with `secret`."
  @spec sign(binary(), binary()) :: String.t()
  def sign(body, secret),
    do: "sha256=" <> Base.encode16(:crypto.mac(:hmac, :sha256, secret, body), case: :lower)

  defp deliver(url, payload, secret, id) do
    headers =
      [{"content-type", "application/json"}] ++
        if(secret, do: [{"x-signature", sign(payload, secret)}], else: [])

    options =
      [
        body: payload,
        headers: headers,
        retry: :transient,
        max_retries: 3,
        receive_timeout: 10_000
      ]
      |> Keyword.merge(Application.get_env(:backend, :webhook_req_options, []))

    case Req.post(url, options) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("[Webhooks] #{id}: callback returned HTTP #{status}")

      {:error, exception} ->
        Logger.warning("[Webhooks] #{id}: callback failed: #{Exception.message(exception)}")
    end
  end
end
