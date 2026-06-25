defmodule AgentSea.Crew.DelegationTest do
  use ExUnit.Case, async: true

  alias AgentSea.{Agent, Capability, Role}
  alias AgentSea.Crew.{Task, Delegation}
  alias AgentSea.Crew.Delegation.{RoundRobin, BestMatch, Auction}
  alias AgentSea.Crews.NoopProvider

  defp cap(name, prof \\ :expert), do: %Capability{name: name, proficiency: prof}

  # Start a real agent process with a role, and return an agent_ref for delegation.
  defp agent_ref(name, capabilities, model \\ "claude-sonnet-4-6") do
    role = %Role{name: to_string(name), capabilities: capabilities}

    config = %Agent.Config{
      name: name,
      model: model,
      provider: {NoopProvider, []},
      role: role
    }

    pid = start_supervised!({Agent, config}, id: name)
    %{name: name, pid: pid, role: role}
  end

  describe "RoundRobin" do
    test "cycles through agents by counter position" do
      agents = [agent_ref(:a, []), agent_ref(:b, []), agent_ref(:c, [])]
      task = Task.new(description: "do")

      picks =
        for i <- 0..3 do
          {:ok, r} = Delegation.select(RoundRobin, task, agents, %{counter: i})
          r.selected_agent
        end

      assert picks == [:a, :b, :c, :a]
    end

    test "errors with no agents" do
      assert {:error, :no_agents} = Delegation.select(RoundRobin, Task.new(description: "x"), [], %{})
    end
  end

  describe "BestMatch" do
    test "selects the agent that can execute with the highest capability score" do
      agents = [
        agent_ref(:junior, [cap("coding", :novice)]),
        agent_ref(:senior, [cap("coding", :master), cap("testing", :expert)]),
        agent_ref(:designer, [cap("design", :master)])
      ]

      task = Task.new(description: "write code", required_capabilities: ["coding"])

      assert {:ok, result} = Delegation.select(BestMatch, task, agents, %{})
      assert result.selected_agent == :senior
      assert result.confidence > 0.5
    end
  end

  describe "Auction" do
    test "confidence criterion selects the most capable bidder" do
      agents = [
        agent_ref(:weak, [cap("coding", :novice)]),
        agent_ref(:strong, [cap("coding", :master)])
      ]

      task = Task.new(description: "code", required_capabilities: ["coding"])

      assert {:ok, %Delegation.Result{selected_agent: :strong}} =
               Delegation.select(Auction, task, agents, %{selection_criteria: :confidence})
    end

    test "cheapest criterion prefers the cheaper model when bids are comparable" do
      agents = [
        agent_ref(:pricey, [cap("coding")], "claude-opus-4-8"),
        agent_ref(:cheap, [cap("coding")], "claude-haiku-4-5")
      ]

      task = Task.new(description: "code", required_capabilities: ["coding"])

      assert {:ok, %Delegation.Result{selected_agent: :cheap}} =
               Delegation.select(Auction, task, agents, %{selection_criteria: :cheapest})
    end

    test "minimum_bid filters out low-confidence bidders" do
      # This agent is missing the required capability → confidence is halved & low.
      agents = [agent_ref(:unqualified, [cap("design")])]
      task = Task.new(description: "code", required_capabilities: ["coding"])

      assert {:error, :no_bids} =
               Delegation.select(Auction, task, agents, %{minimum_bid: 0.5})
    end

    test "records a decision time and lists alternatives" do
      agents = [agent_ref(:a, [cap("coding")]), agent_ref(:b, [cap("coding", :novice)])]
      task = Task.new(description: "code", required_capabilities: ["coding"])

      assert {:ok, result} = Delegation.select(Auction, task, agents, %{})
      assert result.selected_agent == :a
      assert result.decision_time_ms >= 0
      assert result.alternatives == [:b]
    end

    test "errors with no agents" do
      assert {:error, :no_agents} = Delegation.select(Auction, Task.new(description: "x"), [], %{})
    end
  end
end
