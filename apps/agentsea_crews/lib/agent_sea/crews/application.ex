defmodule AgentSea.Crews.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Maps {crew_name, key} -> pid for each crew's coordinator/supervisors.
      {Registry, keys: :unique, name: AgentSea.CrewRegistry}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: AgentSea.Crews.RootSupervisor)
  end
end
