defmodule Tollgate.Server do
  use GenServer

  alias Tollgate.{SlidingWindow, TokenBucket}

  @default_sweep_ms 30_000

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  def token_bucket(server, key, capacity, rate, cost, now) do
    GenServer.call(server, {:token_bucket, key, capacity, rate, cost, now})
  end

  def window(server, key, limit, window_ms, cost, now) do
    GenServer.call(server, {:window, key, limit, window_ms, cost, now})
  end

  def reset(server, key), do: GenServer.call(server, {:reset, key})

  def size(server), do: GenServer.call(server, :size)

  def sweep(server, now), do: GenServer.call(server, {:sweep, now})

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :sweep_interval, @default_sweep_ms)
    table = :ets.new(:tollgate, [:set, :protected])
    schedule(interval)
    {:ok, %{table: table, interval: interval}}
  end

  @impl true
  def handle_call({:token_bucket, key, capacity, rate, cost, now}, _from, %{table: t} = s) do
    ttl = TokenBucket.ttl(capacity, rate)

    {reply, state} =
      case TokenBucket.step(lookup(t, {:bucket, key}), now, capacity, rate, cost) do
        {:ok, state} -> {{:ok, TokenBucket.remaining(state)}, state}
        {:error, wait, state} -> {{:error, wait}, state}
      end

    :ets.insert(t, {{:bucket, key}, state, now + ttl})
    {:reply, reply, s}
  end

  def handle_call({:window, key, limit, window_ms, cost, now}, _from, %{table: t} = s) do
    {reply, state} =
      case SlidingWindow.step(lookup(t, {:window, key}), now, limit, window_ms, cost) do
        {:ok, state} -> {{:ok, SlidingWindow.remaining(state, limit)}, state}
        {:error, wait, state} -> {{:error, wait}, state}
      end

    :ets.insert(t, {{:window, key}, state, now + window_ms})
    {:reply, reply, s}
  end

  def handle_call({:reset, key}, _from, %{table: t} = s) do
    :ets.delete(t, {:bucket, key})
    :ets.delete(t, {:window, key})
    {:reply, :ok, s}
  end

  def handle_call(:size, _from, %{table: t} = s), do: {:reply, :ets.info(t, :size), s}

  def handle_call({:sweep, now}, _from, %{table: t} = s), do: {:reply, expire(t, now), s}

  @impl true
  def handle_info(:sweep, %{table: t, interval: interval} = s) do
    expire(t, System.monotonic_time(:millisecond))
    schedule(interval)
    {:noreply, s}
  end

  def handle_info(_message, s), do: {:noreply, s}

  defp lookup(table, key) do
    case :ets.lookup(table, key) do
      [{^key, state, _expires}] -> state
      [] -> nil
    end
  end

  defp expire(table, now) do
    :ets.select_delete(table, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
  end

  defp schedule(interval) when is_integer(interval) and interval > 0 do
    Process.send_after(self(), :sweep, interval)
  end

  defp schedule(_interval), do: :ok
end
