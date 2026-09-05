defmodule Tollgate.TokenBucket do
  @type state :: {tokens :: float(), last_ms :: integer()}

  @spec step(state | nil, integer(), pos_integer(), number(), pos_integer()) ::
          {:ok, state} | {:error, pos_integer(), state}
  def step(state, now, capacity, refill_per_sec, cost) do
    {tokens, _last} = refill(state, now, capacity, refill_per_sec)

    if tokens >= cost do
      {:ok, {tokens - cost, now}}
    else
      wait = ceil((cost - tokens) * 1000 / refill_per_sec)
      {:error, max(wait, 1), {tokens, now}}
    end
  end

  @spec remaining(state) :: non_neg_integer()
  def remaining({tokens, _last}), do: trunc(tokens)

  @spec ttl(pos_integer(), number()) :: pos_integer()
  def ttl(capacity, refill_per_sec), do: ceil(capacity * 1000 / refill_per_sec)

  defp refill(nil, now, capacity, _rate), do: {capacity * 1.0, now}

  defp refill({tokens, last}, now, capacity, rate) do
    elapsed = max(now - last, 0)
    {min(capacity * 1.0, tokens + elapsed * rate / 1000), now}
  end
end
