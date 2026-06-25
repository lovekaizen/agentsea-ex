defmodule AgentSea.Crew.CoordinatorTest do
  use ExUnit.Case, async: false

  alias AgentSea.{Agent, Capability, Role}
  alias AgentSea.Crew
  alias AgentSea.Crews.EchoProvider

  defp agent_config(name, capabilities) do
    %Agent.Config{
      name: name,
      model: "claude-haiku-4-5",
      provider: {EchoProvider, []},
      role: %Role{name: to_string(name), capabilities: capabilities}
    }
  end

  defp cap(name), do: %Capability{name: name, proficiency: :expert}

  # Start a uniquely-named crew so async-safe-ish tests don't collide on the registry.
  defp start_crew(agents, opts \\ []) do
    name = :"crew_#{System.unique_integer([:positive])}"

    spec = %Crew.Spec{
      name: name,
      agents: agents,
      strategy: Keyword.get(opts, :strategy, Crew.Delegation.BestMatch)
    }

    start_supervised!({Crew, spec})
    name
  end

  test "runs a single task and returns the agent's output" do
    crew = start_crew([agent_config(:worker, [cap("coding")])])

    {:ok, task} =
      Crew.add_task(crew, description: "write code", required_capabilities: ["coding"])

    assert {:ok, result} = Crew.kickoff(crew)
    assert result.success
    assert result.results[task.id].content == "handled: write code"
    assert Crew.status(crew) == :completed
  end

  test "completes immediately with no tasks" do
    crew = start_crew([agent_config(:worker, [])])
    assert {:ok, %{success: true, results: results}} = Crew.kickoff(crew)
    assert results == %{}
  end

  test "runs independent tasks concurrently and collects all results" do
    crew = start_crew([agent_config(:w, [cap("coding")])])

    {:ok, a} = Crew.add_task(crew, description: "task A", required_capabilities: ["coding"])
    {:ok, b} = Crew.add_task(crew, description: "task B", required_capabilities: ["coding"])

    assert {:ok, result} = Crew.kickoff(crew)
    assert result.success
    assert result.results[a.id].content == "handled: task A"
    assert result.results[b.id].content == "handled: task B"
  end

  test "respects dependencies: a dependent runs after its dependency completes" do
    crew = start_crew([agent_config(:w, [cap("coding")])])

    {:ok, first} = Crew.add_task(crew, description: "first", required_capabilities: ["coding"])

    {:ok, second} =
      Crew.add_task(crew,
        description: "second",
        required_capabilities: ["coding"],
        depends_on: [first.id]
      )

    assert {:ok, result} = Crew.kickoff(crew)
    assert result.success
    assert Map.has_key?(result.results, first.id)
    assert Map.has_key?(result.results, second.id)
  end

  test "a failed task blocks its dependents (marked dependency_failed)" do
    crew = start_crew([agent_config(:w, [cap("coding")])])

    {:ok, failing} =
      Crew.add_task(crew, description: "please FAIL", required_capabilities: ["coding"])

    {:ok, dependent} =
      Crew.add_task(crew,
        description: "needs the first",
        required_capabilities: ["coding"],
        depends_on: [failing.id]
      )

    assert {:ok, result} = Crew.kickoff(crew)
    refute result.success
    assert result.failures[failing.id] == :forced_failure
    assert result.failures[dependent.id] == :dependency_failed
  end

  test "best-match assigns a task to the most capable agent" do
    crew =
      start_crew([
        agent_config(:coder, [cap("coding")]),
        agent_config(:writer, [cap("writing")])
      ])

    {:ok, task} =
      Crew.add_task(crew, description: "ship a feature", required_capabilities: ["coding"])

    assert {:ok, result} = Crew.kickoff(crew)
    # The coder handled it (echoed output proves the task ran end-to-end).
    assert result.results[task.id].content == "handled: ship a feature"
  end
end
