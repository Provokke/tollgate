defmodule Tollgate do
  alias Tollgate.Server

  @type result :: {:ok, non_neg_integer()} | {:error, pos_integer()}

  @spec check_token_bucket(term(), keyword()) :: result()
  def check_token_bucket(key, opts) do
    capacity = Keyword.fetch!(opts, :capacity)
    rate = Keyword.fetch!(opts, :refill_per_sec)
    cost = Keyword.get(opts, :cost, 1)
    Server.token_bucket(server(opts), key, capacity, rate, cost, now(opts))
  end

  @spec check_window(term(), keyword()) :: result()
  def check_window(key, opts) do
    limit = Keyword.fetch!(opts, :limit)
    window_ms = Keyword.fetch!(opts, :window_ms)
    cost = Keyword.get(opts, :cost, 1)
    Server.window(server(opts), key, limit, window_ms, cost, now(opts))
  end

  @spec reset(term(), keyword()) :: :ok
  def reset(key, opts \\ []), do: Server.reset(server(opts), key)

  defp server(opts), do: Keyword.get(opts, :server, Server)

  defp now(opts), do: Keyword.get_lazy(opts, :now, fn -> System.monotonic_time(:millisecond) end)
end
