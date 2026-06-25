defmodule AgentSea.Crew do
  @moduledoc """
  A crew of agents that collaborate on a task DAG.

  Starting a crew boots a supervision subtree (a `Task.Supervisor`, a
  `DynamicSupervisor` of agents, and a coordinator). Tasks are added, then
  `kickoff/1` runs them — dispatching ready tasks to agents via the configured
  delegation strategy, running independent tasks concurrently, and unlocking
  dependents as results arrive.

  ## Example

      spec = %AgentSea.Crew.Spec{
        name: :research_crew,
        strategy: AgentSea.Crew.Delegation.BestMatch,
        agents: [researcher_config, writer_config]
      }

      {:ok, _sup} = AgentSea.Crew.start_link(spec)
      AgentSea.Crew.add_task(:research_crew, description: "Research X", required_capabilities: ["research"])
      {:ok, result} = AgentSea.Crew.kickoff(:research_crew)
  """

  defmodule Spec do
    @moduledoc "Declarative crew configuration."

    @enforce_keys [:name, :agents]
    defstruct [
      :name,
      :agents,
      strategy: AgentSea.Crew.Delegation.BestMatch,
      delegation_ctx: %{}
    ]

    @type t :: %__MODULE__{
            name: term(),
            agents: [AgentSea.Agent.Config.t()],
            strategy: module(),
            delegation_ctx: map()
          }
  end

  @doc "Start a crew supervision subtree from a `Spec`."
  def start_link(%Spec{} = spec), do: AgentSea.Crew.Supervisor.start_link(spec)

  @doc false
  def child_spec(%Spec{name: name} = spec) do
    %{id: {:crew, name}, start: {__MODULE__, :start_link, [spec]}, type: :supervisor}
  end

  @doc "Add a task to the crew (only while idle). Accepts `AgentSea.Crew.Task.new/1` attrs."
  defdelegate add_task(crew, attrs), to: AgentSea.Crew.Coordinator

  @doc "Run the crew to completion; returns `{:ok, result}` with results & failures."
  defdelegate kickoff(crew), to: AgentSea.Crew.Coordinator

  @doc "Current crew status: `:idle | :running | :completed`."
  defdelegate status(crew), to: AgentSea.Crew.Coordinator
end
