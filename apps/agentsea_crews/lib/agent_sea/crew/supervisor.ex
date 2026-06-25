defmodule AgentSea.Crew.Supervisor do
  @moduledoc """
  Per-crew supervision subtree: a `Task.Supervisor` for delegated work, a
  `DynamicSupervisor` for the crew's agents, and the coordinator. All three are
  registered in `AgentSea.CrewRegistry` keyed by `{crew_name, key}`.
  """

  use Supervisor

  alias AgentSea.Crew

  def start_link(%Crew.Spec{name: name} = spec) do
    Supervisor.start_link(__MODULE__, spec, name: via(name, :supervisor))
  end

  @impl true
  def init(%Crew.Spec{name: name} = spec) do
    children = [
      {Task.Supervisor, name: via(name, :task_sup)},
      {DynamicSupervisor, name: via(name, :agent_sup), strategy: :one_for_one},
      {Crew.Coordinator, spec}
    ]

    # Coordinator starts last, so the task/agent supervisors are already up.
    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc "Build a `:via` tuple for a crew's registered process (`:supervisor`, `:task_sup`, `:agent_sup`, `:coordinator`)."
  def via(name, key), do: {:via, Registry, {AgentSea.CrewRegistry, {name, key}}}
end
