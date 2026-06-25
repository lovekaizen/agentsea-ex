defmodule AgentSea.Crew.ControlTest do
  use ExUnit.Case, async: false

  alias AgentSea.{Agent, Capability, Role}
  alias AgentSea.Crew
  alias AgentSea.Crews.{BlockingProvider, EchoProvider}

  defp blocking_agent(name) do
    %Agent.Config{
      name: name,
      model: "claude-haiku-4-5",
      provider: {BlockingProvider, [notify: self()]},
      role: %Role{
        name: to_string(name),
        capabilities: [%Capability{name: "coding", proficiency: :expert}]
      }
    }
  end

  defp echo_agent(name) do
    %Agent.Config{
      name: name,
      model: "claude-haiku-4-5",
      provider: {EchoProvider, []},
      role: %Role{name: to_string(name), capabilities: []}
    }
  end

  defp start_crew(agents) do
    name = :"ctl_#{System.unique_integer([:positive])}"

    start_supervised!(
      {Crew, %Crew.Spec{name: name, agents: agents, strategy: Crew.Delegation.BestMatch}}
    )

    name
  end

  describe "transition guards" do
    test "pause/resume/abort are rejected while idle" do
      crew = start_crew([echo_agent(:w)])
      assert {:error, {:invalid_status, :idle}} = Crew.pause(crew)
      assert {:error, {:invalid_status, :idle}} = Crew.resume(crew)
      assert {:error, {:invalid_status, :idle}} = Crew.abort(crew)
    end

    test "resume is rejected while running (not paused)" do
      crew = start_crew([blocking_agent(:w)])
      {:ok, _} = Crew.add_task(crew, description: "work", required_capabilities: ["coding"])

      caller = Task.async(fn -> Crew.kickoff(crew) end)
      assert_receive {:running, pid, _}, 2_000

      assert {:error, {:invalid_status, :running}} = Crew.resume(crew)

      send(pid, :release)
      assert {:ok, %{success: true}} = Task.await(caller)
    end
  end

  test "pause holds back new dispatch; resume continues to completion" do
    crew = start_crew([blocking_agent(:w)])

    {:ok, a} = Crew.add_task(crew, description: "A", required_capabilities: ["coding"])

    {:ok, _b} =
      Crew.add_task(crew, description: "B", required_capabilities: ["coding"], depends_on: [a.id])

    caller = Task.async(fn -> Crew.kickoff(crew) end)

    # A is dispatched and in-flight.
    assert_receive {:running, pid_a, "A"}, 2_000

    assert :ok = Crew.pause(crew)
    assert Crew.status(crew) == :paused

    # Finish A while paused — B must NOT be dispatched yet.
    send(pid_a, :release)
    refute_receive {:running, _pid, "B"}, 300
    assert Crew.status(crew) == :paused

    # Resume: B is now dispatched.
    assert :ok = Crew.resume(crew)
    assert_receive {:running, pid_b, "B"}, 2_000
    send(pid_b, :release)

    assert {:ok, result} = Task.await(caller)
    assert result.success
    assert Crew.status(crew) == :completed
  end

  test "abort cancels in-flight work and fails the kickoff caller" do
    crew = start_crew([blocking_agent(:w)])
    {:ok, _} = Crew.add_task(crew, description: "long task", required_capabilities: ["coding"])

    caller = Task.async(fn -> Crew.kickoff(crew) end)
    assert_receive {:running, _pid, "long task"}, 2_000

    assert :ok = Crew.abort(crew)
    assert {:error, :aborted} = Task.await(caller)
    assert Crew.status(crew) == :aborted
  end
end
