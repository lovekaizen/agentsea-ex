defmodule AgentSea.GatewayTest do
  use ExUnit.Case, async: false

  alias AgentSea.Gateway
  alias AgentSea.Gateway.{Config, Provider, CircuitBreaker}
  alias AgentSea.Gateway.Router.{Failover, RoundRobin, CostOptimized, LatencyOptimized}
  alias AgentSea.Gateway.TestProvider

  # Unique provider name per test, so global fuses don't carry state across tests.
  defp pname(prefix), do: :"#{prefix}_#{System.unique_integer([:positive])}"

  defp provider(name, model, opts),
    do: %Provider{name: name, module: TestProvider, model: model, opts: opts}

  defp start_gateway(providers, strategy) do
    start_supervised!({Gateway, %Config{providers: providers, strategy: strategy}})
  end

  test "routes to a provider and returns its tagged response" do
    p = provider(pname(:solo), "claude-haiku-4-5", behavior: :ok, tag: "from-solo")
    gw = start_gateway([p], Failover)

    assert {:ok, response, served_by} = Gateway.completion(gw, [])
    assert response.content == "from-solo"
    assert served_by == p.name
  end

  test "fails over to the next provider when the first errors" do
    bad = provider(pname(:bad), "claude-opus-4-8", behavior: :error)
    good = provider(pname(:good), "claude-haiku-4-5", behavior: :ok, tag: "backup")
    gw = start_gateway([bad, good], Failover)

    assert {:ok, response, served_by} = Gateway.completion(gw, [])
    assert response.content == "backup"
    assert served_by == good.name
  end

  test "returns an error when all providers fail" do
    a = provider(pname(:a), "m", behavior: :error)
    b = provider(pname(:b), "m", behavior: :error)
    gw = start_gateway([a, b], Failover)

    assert {:error, :all_providers_unavailable} = Gateway.completion(gw, [])
  end

  test "round-robin spreads successive requests across providers" do
    a = provider(pname(:rr_a), "m", behavior: :ok, tag: "a")
    b = provider(pname(:rr_b), "m", behavior: :ok, tag: "b")
    c = provider(pname(:rr_c), "m", behavior: :ok, tag: "c")
    gw = start_gateway([a, b, c], RoundRobin)

    served =
      for _ <- 1..3 do
        {:ok, _resp, name} = Gateway.completion(gw, [])
        name
      end

    assert Enum.sort(served) == Enum.sort([a.name, b.name, c.name])
  end

  test "cost-optimized routes to the cheaper model first" do
    pricey = provider(pname(:pricey), "claude-opus-4-8", behavior: :ok, tag: "pricey")
    cheap = provider(pname(:cheap), "claude-haiku-4-5", behavior: :ok, tag: "cheap")
    # Configured pricey-first, but cost routing should still pick cheap.
    gw = start_gateway([pricey, cheap], CostOptimized)

    assert {:ok, response, served_by} = Gateway.completion(gw, [])
    assert response.content == "cheap"
    assert served_by == cheap.name
  end

  test "records provider health (latency + call counts)" do
    p = provider(pname(:health), "m", behavior: :ok, tag: "x")
    gw = start_gateway([p], Failover)

    {:ok, _resp, _name} = Gateway.completion(gw, [])

    health = Gateway.health(gw)
    assert %{calls: 1, errors: 0, latency_ms: ms} = health[p.name]
    assert is_integer(ms)
  end

  test "latency-optimized prefers the provider with lower observed latency" do
    fast = provider(pname(:fast), "m", behavior: :ok, tag: "fast", sleep_ms: 0)
    slow = provider(pname(:slow), "m", behavior: :ok, tag: "slow", sleep_ms: 25)
    # Configured slow-first so only latency ordering can flip them.
    gw = start_gateway([slow, fast], LatencyOptimized)

    # Warm up both so health has latency for each (first call: no health → config
    # order, so `slow` serves; second: still unknown for fast → ... seed both
    # explicitly by excluding in turn).
    {:ok, _, _} = Gateway.completion(gw, [], exclude: [fast.name])
    {:ok, _, _} = Gateway.completion(gw, [], exclude: [slow.name])

    # Now both have recorded latency; fast should win.
    assert {:ok, response, served_by} = Gateway.completion(gw, [])
    assert served_by == fast.name
    assert response.content == "fast"
  end

  describe "circuit breaker" do
    test "blows after repeated failures and ask/1 reports it" do
      name = pname(:cb)
      CircuitBreaker.ensure(name)
      assert CircuitBreaker.ask(name) == :ok

      # Tolerance is 1 melt/window; the 2nd melt blows it.
      CircuitBreaker.melt(name)
      CircuitBreaker.melt(name)
      # Give :fuse a moment to process the async melt.
      Process.sleep(20)

      assert CircuitBreaker.ask(name) == :blown
    end

    test "a blown provider is excluded from routing" do
      blown = provider(pname(:blown), "m", behavior: :ok, tag: "blown")
      ok = provider(pname(:ok), "m", behavior: :ok, tag: "ok")
      gw = start_gateway([blown, ok], Failover)

      # Blow the first provider's fuse directly.
      CircuitBreaker.melt(blown.name)
      CircuitBreaker.melt(blown.name)
      Process.sleep(20)

      assert {:ok, response, served_by} = Gateway.completion(gw, [])
      assert served_by == ok.name
      assert response.content == "ok"
    end
  end
end
