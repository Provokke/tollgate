defmodule TollgateTest do
  use ExUnit.Case, async: true

  alias Tollgate.{SlidingWindow, TokenBucket}

  describe "TokenBucket.step/5" do
    test "a new bucket starts full" do
      assert {:ok, {tokens, 0}} = TokenBucket.step(nil, 0, 5, 1, 1)
      assert tokens == 4.0
    end

    test "refuses once empty and reports the wait" do
      {:ok, s1} = TokenBucket.step(nil, 0, 1, 2, 1)
      assert {:error, 500, _} = TokenBucket.step(s1, 0, 1, 2, 1)
    end

    test "refills over time but never beyond capacity" do
      {:ok, s1} = TokenBucket.step(nil, 0, 2, 1, 2)
      assert {:ok, s2} = TokenBucket.step(s1, 1_000, 2, 1, 1)
      assert TokenBucket.remaining(s2) == 0
      assert {:ok, s3} = TokenBucket.step(s2, 100_000, 2, 1, 1)
      assert TokenBucket.remaining(s3) == 1
    end
  end

  describe "SlidingWindow.step/5" do
    test "allows up to the limit" do
      {:ok, s1} = SlidingWindow.step(nil, 0, 2, 1000)
      {:ok, s2} = SlidingWindow.step(s1, 10, 2, 1000)
      assert {:error, 990, _} = SlidingWindow.step(s2, 10, 2, 1000)
    end

    test "old hits fall out of the window" do
      {:ok, s1} = SlidingWindow.step(nil, 0, 1, 1000)
      assert {:error, 1, _} = SlidingWindow.step(s1, 999, 1, 1000)
      assert {:ok, [1000]} = SlidingWindow.step(s1, 1000, 1, 1000)
    end

    test "remaining never goes negative" do
      assert SlidingWindow.remaining([1, 2, 3], 2) == 0
    end
  end

  describe "public API" do
    setup do
      name = :"server_#{System.unique_integer([:positive])}"
      start_supervised!({Tollgate.Server, name: name, sweep_interval: 0})
      {:ok, server: name}
    end

    test "token bucket through the server", %{server: server} do
      opts = [capacity: 3, refill_per_sec: 1, server: server]
      assert {:ok, 2} = Tollgate.check_token_bucket(:a, [now: 0] ++ opts)
      assert {:ok, 1} = Tollgate.check_token_bucket(:a, [now: 0] ++ opts)
      assert {:ok, 0} = Tollgate.check_token_bucket(:a, [now: 0] ++ opts)
      assert {:error, 1000} = Tollgate.check_token_bucket(:a, [now: 0] ++ opts)
      assert {:ok, 0} = Tollgate.check_token_bucket(:a, [now: 1000] ++ opts)
    end

    test "keys are independent", %{server: server} do
      opts = [limit: 1, window_ms: 1000, server: server, now: 0]
      assert {:ok, 0} = Tollgate.check_window(:a, opts)
      assert {:error, _} = Tollgate.check_window(:a, opts)
      assert {:ok, 0} = Tollgate.check_window(:b, opts)
    end

    test "reset clears state", %{server: server} do
      opts = [limit: 1, window_ms: 1000, server: server, now: 0]
      assert {:ok, 0} = Tollgate.check_window(:a, opts)
      assert :ok = Tollgate.reset(:a, server: server)
      assert {:ok, 0} = Tollgate.check_window(:a, opts)
    end

    test "sweep drops expired entries", %{server: server} do
      Tollgate.check_window(:a, limit: 1, window_ms: 100, server: server, now: 0)
      assert Tollgate.Server.size(server) == 1
      assert Tollgate.Server.sweep(server, 50) == 0
      assert Tollgate.Server.sweep(server, 500) == 1
      assert Tollgate.Server.size(server) == 0
    end

    test "concurrent callers never exceed the limit", %{server: server} do
      opts = [limit: 10, window_ms: 60_000, server: server]

      results =
        1..50
        |> Task.async_stream(fn _ -> Tollgate.check_window(:shared, opts) end, max_concurrency: 20)
        |> Enum.map(fn {:ok, r} -> r end)

      assert Enum.count(results, &match?({:ok, _}, &1)) == 10
    end
  end

  test "the default server runs under the application supervisor" do
    assert Process.whereis(Tollgate.Server)
    assert {:ok, 0} = Tollgate.check_window(:default_key, limit: 1, window_ms: 10_000)
  end
end
