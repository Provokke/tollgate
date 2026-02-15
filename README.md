<div align="center">

# tollgate

Token bucket and sliding-window rate limiters for Elixir, backed by a GenServer and ETS. No dependencies.

![License](https://img.shields.io/badge/LICENSE-MIT-blue?style=for-the-badge)  ![Language](https://img.shields.io/badge/ELIXIR-4B275F?style=for-the-badge&logo=elixir&logoColor=white)  ![Tests](https://img.shields.io/badge/TESTS-12-brightgreen?style=for-the-badge)

Refer to [LICENSE](LICENSE) for the legal bits.

</div>

## What's in it

- A token bucket: bursts up to a capacity, refilled at a steady rate per second.
- A sliding window: counts hits in the last N milliseconds and refuses once a limit is reached.
- Both return `{:ok, remaining}` or `{:error, retry_after_ms}`, and accept `cost:`, `now:` (milliseconds, handy for tests) and `server:` options.
- A supervised `Tollgate.Server` that owns the ETS table and sweeps expired keys on an interval, plus `reset/2` to clear a key.

```elixir
case Tollgate.check_token_bucket({:user, 42}, capacity: 10, refill_per_sec: 2) do
  {:ok, remaining} -> handle(remaining)
  {:error, retry_after_ms} -> reject(retry_after_ms)
end

Tollgate.check_window("10.0.0.1", limit: 100, window_ms: 60_000)
```

To run an extra server, add `{Tollgate.Server, name: MyLimiter, sweep_interval: 10_000}` to your supervision tree and pass `server: MyLimiter`.

## 🏗️ Architecture

```
 Tollgate (public API)  check_token_bucket / check_window / reset
        │  GenServer.call
        ▼
 Tollgate.Server  ── one process, one :ets table {key, state, expires_at}
   │     :sweep timer ─▶ select_delete rows where expires_at < now
   ├─ Tollgate.TokenBucket    step(state, now, capacity, rate, cost)
   │       state = {tokens, last_ms}          pure, no clock of its own
   └─ Tollgate.SlidingWindow  step(state, now, limit, window_ms, cost)
           state = [timestamps, newest first]  pure
 Tollgate.Application ─ supervises the default Tollgate.Server
```

- `TokenBucket` and `SlidingWindow` are pure modules: state and a timestamp in, new state out. That's why the tests don't need a clock.
- The server serialises every check through one process, so decisions are exact. The cost is that throughput is capped at what one process can handle.
- Keys are stored as `{:bucket, key}` and `{:window, key}`, so the same key can be used with both algorithms. Each row carries an expiry (the time to refill from empty, or the window length) and the sweep deletes anything past it.
- Setting `sweep_interval: 0` turns the sweep timer off, which is what the tests do.

## 🚀 Quick start

```
mix test
```

Needs Elixir 1.15 or later. A three-token bucket with a clock you control, then a two-hit window:

```elixir
for _ <- 1..4, do: Tollgate.check_token_bucket(:me, capacity: 3, refill_per_sec: 1, now: 0)
Tollgate.check_token_bucket(:me, capacity: 3, refill_per_sec: 1, now: 2000)
Tollgate.check_window("ip", limit: 2, window_ms: 1000, now: 0)
```

which return `{:ok, 2}`, `{:ok, 1}`, `{:ok, 0}`, `{:error, 1000}`, then `{:ok, 1}` after two seconds, and `{:ok, 1}` for the window.

## 🧪 Testing

12 tests, all passing (ExUnit):

- `TokenBucket.step/5` (3): a new bucket starts full, it refuses once empty and reports the wait, and it refills over time but never beyond capacity.
- `SlidingWindow.step/5` (3): allows up to the limit, old hits fall out of the window, and remaining never goes negative.
- Public API through a supervised server (5): the token bucket end to end, independent keys, `reset`, `sweep` dropping expired entries, and concurrent callers never exceeding the limit.
- The default server runs under the application supervisor (1).

## ⚠️ Honest limits

- State is in memory and per node, so limits aren't shared across a cluster and are lost on restart.
- The sliding window stores one timestamp per hit, so memory grows with the limit. It's a poor fit for very large limits.

## Licence

MIT.
