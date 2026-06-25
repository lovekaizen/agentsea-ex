defmodule AgentSea.Crew.TelemetryTest do
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

  test "emits crew kickoff and task lifecycle events" do
    name = :"tcrew_#{System.unique_integer([:positive])}"
    caps = [%Capability{name: "coding", proficiency: :expert}]
    spec = %Crew.Spec{name: name, agents: [agent_config(:w, caps)]}

    start_supervised!({Crew, spec})
    {:ok, task} = Crew.add_task(name, description: "code", required_capabilities: ["coding"])

    ref =
      :telemetry_test.attach_event_handlers(self(), [
        [:agentsea, :crew, :kickoff, :start],
        [:agentsea, :crew, :kickoff, :stop],
        [:agentsea, :crew, :task, :start],
        [:agentsea, :crew, :task, :stop]
      ])

    assert {:ok, %{success: true}} = Crew.kickoff(name)

    assert_receive {[:agentsea, :crew, :kickoff, :start], ^ref, _meas,
                    %{crew: ^name, task_count: 1}}

    assert_receive {[:agentsea, :crew, :task, :start], ^ref, _meas,
                    %{crew: ^name, task_id: task_id, agent: :w}}

    assert task_id == task.id

    assert_receive {[:agentsea, :crew, :task, :stop], ^ref, _meas, %{crew: ^name, outcome: :ok}}

    assert_receive {[:agentsea, :crew, :kickoff, :stop], ^ref, %{duration: _},
                    %{crew: ^name, success: true}}
  end
end
