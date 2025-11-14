defmodule Tollgate.SlidingWindow do
  @type state :: [integer()]

  @spec step(state | nil, integer(), pos_integer(), pos_integer(), pos_integer()) ::
          {:ok, state} | {:error, pos_integer(), state}
  def step(state, now, limit, window_ms, cost \\ 1) do
    cutoff = now - window_ms
    kept = Enum.filter(state || [], &(&1 > cutoff))

    if length(kept) + cost <= limit do
      {:ok, List.duplicate(now, cost) ++ kept}
    else
      {:error, retry_after(kept, limit, cost, now, window_ms), kept}
    end
  end

  @spec remaining(state, pos_integer()) :: non_neg_integer()
  def remaining(state, limit), do: max(limit - length(state), 0)

  defp retry_after(kept, limit, cost, now, window_ms) do
    needed = max(length(kept) + cost - limit, 1)
    oldest_first = Enum.reverse(kept)
    pivot = Enum.at(oldest_first, min(needed, length(oldest_first)) - 1)
    max(pivot + window_ms - now, 1)
  end
end
