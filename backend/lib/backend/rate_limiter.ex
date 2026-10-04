defmodule Backend.RateLimiter do
  @moduledoc """
  Sliding-window per-phone-number rate limiter backed by Cachex.

  Tracks Unix timestamps of each SMS send within the last hour.
  Old timestamps outside the window are pruned on every check.

  Config key: :rate_limit_per_hour (default: 3)
  """

  require Logger

  @cache :rate_limit_store
  # 1-hour window
  @window_seconds 3_600

  @doc """
  Check if sending is allowed for `phone`.

  Returns:
    - `{:ok, remaining}`                       — allowed; remaining sends this hour
    - `{:error, :rate_limited, retry_after}`   — blocked; seconds until slot frees up
  """
  @spec check(String.t()) :: {:ok, non_neg_integer()} | {:error, :rate_limited, non_neg_integer()}
  def check(phone) do
    limit = Application.get_env(:backend, :rate_limit_per_hour, 3)
    now = System.os_time(:second)
    ts = live_timestamps(phone, now)

    if length(ts) < limit do
      {:ok, limit - length(ts)}
    else
      oldest = Enum.min(ts)
      retry_after = @window_seconds - (now - oldest)
      {:error, :rate_limited, max(retry_after, 1)}
    end
  end

  @doc "Record a successful send for `phone`. Call after the SMS is dispatched."
  @spec record(String.t()) :: :ok
  def record(phone) do
    now = System.os_time(:second)
    existing = live_timestamps(phone, now)
    updated = [now | existing]

    Cachex.put(@cache, phone, updated, ttl: @window_seconds * 1_000)
    Logger.debug("[RateLimiter] #{phone} → #{length(updated)} sends this hour")
    :ok
  end

  @doc "Remaining sends in the current window for `phone`."
  @spec remaining(String.t()) :: non_neg_integer()
  def remaining(phone) do
    limit = Application.get_env(:backend, :rate_limit_per_hour, 3)
    now = System.os_time(:second)
    max(limit - length(live_timestamps(phone, now)), 0)
  end

  # Only keep timestamps within the rolling window
  defp live_timestamps(phone, now) do
    case Cachex.get(@cache, phone) do
      {:ok, nil} -> []
      {:ok, ts} -> Enum.filter(ts, &(now - &1 < @window_seconds))
      _ -> []
    end
  end
end
