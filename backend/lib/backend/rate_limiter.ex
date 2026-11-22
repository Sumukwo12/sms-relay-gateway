defmodule Backend.RateLimiter do
  @moduledoc """
  Sliding-window rate limiter backed by Cachex.

  Tracks Unix timestamps of each SMS send within a 1-hour rolling window.
  Old timestamps outside the window are pruned on every check.

  Supports:
    - Per-phone rate limits (default: 3/hour, env: RATE_LIMIT_PER_HOUR)
    - Per-client-IP rate limits (default: 5/hour, env: RATE_LIMIT_PER_IP_PER_HOUR)
    - Global rate limit cap (default: 100/hour, env: RATE_LIMIT_GLOBAL_PER_HOUR)
  """

  require Logger
  alias Backend.PhoneUtils

  @cache :rate_limit_store
  # 1-hour rolling window
  @window_seconds 3_600

  @doc """
  Atomically check and reserve a rate limit slot for `phone`, `ip` (optional), and global.

  Returns:
    - `{:ok, reservation}`                     — allowed and reserved
    - `{:error, :rate_limited, retry_after}`   — blocked; seconds until slot frees up
  """
  @spec reserve(String.t(), String.t() | nil) ::
          {:ok, map()} | {:error, :rate_limited, non_neg_integer()}
  def reserve(phone, ip \\ nil) when is_binary(phone) do
    now = System.os_time(:second)
    ip_key = if ip && is_binary(ip) && ip != "", do: "ip:#{ip}", else: nil

    buckets =
      [
        {phone, phone_limit()},
        {"global", global_limit()}
      ] ++ if ip_key, do: [{ip_key, ip_limit()}], else: []

    keys = Enum.map(buckets, &elem(&1, 0))

    result =
      Cachex.transaction(@cache, keys, fn _ ->
        # 1. Check all buckets
        check_result =
          Enum.reduce_while(buckets, :ok, fn {key, limit}, :ok ->
            ts = get_live_timestamps(key, now)

            if length(ts) < limit do
              {:cont, :ok}
            else
              oldest = Enum.min(ts)
              retry_after = max(@window_seconds - (now - oldest), 1)
              {:halt, {:error, :rate_limited, retry_after}}
            end
          end)

        case check_result do
          :ok ->
            # 2. Reserve in all buckets
            Enum.each(buckets, fn {key, _limit} ->
              existing = get_live_timestamps(key, now)
              updated = [now | existing]
              Cachex.put(@cache, key, updated, ttl: @window_seconds * 1_000)
            end)

            Logger.debug(
              "[RateLimiter] Reserved slot for #{PhoneUtils.mask(phone)} ip=#{inspect(ip)}"
            )

            {:ok, %{phone: phone, ip: ip, timestamp: now}}

          {:error, :rate_limited, _} = err ->
            err
        end
      end)

    case result do
      {:ok, res} ->
        res

      {:error, reason} ->
        Logger.error("[RateLimiter] Transaction error during reserve: #{inspect(reason)}")
        {:error, :rate_limited, 60}
    end
  end

  @doc """
  Release a reserved rate limit slot if SMS delivery failed.
  """
  @spec release(map() | String.t()) :: :ok
  def release(%{phone: phone, ip: ip, timestamp: ts}) do
    ip_key = if ip && is_binary(ip) && ip != "", do: "ip:#{ip}", else: nil

    keys =
      [phone, "global"] ++ if ip_key, do: [ip_key], else: []

    Cachex.transaction(@cache, keys, fn _ ->
      Enum.each(keys, fn key ->
        case Cachex.get(@cache, key) do
          {:ok, list} when is_list(list) ->
            updated = List.delete(list, ts)
            Cachex.put(@cache, key, updated, ttl: @window_seconds * 1_000)

          _ ->
            :ok
        end
      end)
    end)

    Logger.debug("[RateLimiter] Released slot for #{PhoneUtils.mask(phone)} ip=#{inspect(ip)}")
    :ok
  end

  def release(phone) when is_binary(phone) do
    Cachex.transaction(@cache, [phone, "global"], fn _ ->
      Enum.each([phone, "global"], fn key ->
        case Cachex.get(@cache, key) do
          {:ok, [_head | tail]} ->
            Cachex.put(@cache, key, tail, ttl: @window_seconds * 1_000)

          _ ->
            :ok
        end
      end)
    end)

    :ok
  end

  def release(_), do: :ok

  @doc """
  Check if sending is allowed for `phone` without reserving.

  Returns:
    - `{:ok, remaining}`                       — allowed; remaining sends this hour
    - `{:error, :rate_limited, retry_after}`   — blocked; seconds until slot frees up
  """
  @spec check(String.t()) :: {:ok, non_neg_integer()} | {:error, :rate_limited, non_neg_integer()}
  def check(phone) when is_binary(phone) do
    limit = phone_limit()
    now = System.os_time(:second)
    ts = get_live_timestamps(phone, now)

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
  def record(phone) when is_binary(phone) do
    reserve(phone)
    :ok
  end

  @doc "Remaining sends in the current window for `phone`."
  @spec remaining(String.t()) :: non_neg_integer()
  def remaining(phone) when is_binary(phone) do
    limit = phone_limit()
    now = System.os_time(:second)
    max(limit - length(get_live_timestamps(phone, now)), 0)
  end

  @doc "Remaining sends in the current window for client `ip`."
  @spec remaining_ip(String.t()) :: non_neg_integer()
  def remaining_ip(ip) when is_binary(ip) do
    limit = ip_limit()
    now = System.os_time(:second)
    max(limit - length(get_live_timestamps("ip:#{ip}", now)), 0)
  end

  @doc "Remaining global sends in the current window."
  @spec remaining_global() :: non_neg_integer()
  def remaining_global do
    limit = global_limit()
    now = System.os_time(:second)
    max(limit - length(get_live_timestamps("global", now)), 0)
  end

  # Only keep timestamps within the rolling window
  defp get_live_timestamps(key, now) do
    case Cachex.get(@cache, key) do
      {:ok, nil} -> []
      {:ok, ts} when is_list(ts) -> Enum.filter(ts, &(now - &1 < @window_seconds))
      _ -> []
    end
  end

  defp phone_limit, do: Application.get_env(:backend, :rate_limit_per_hour, 3)
  defp ip_limit, do: Application.get_env(:backend, :rate_limit_per_ip_per_hour, 5)
  defp global_limit, do: Application.get_env(:backend, :rate_limit_global_per_hour, 100)
end
