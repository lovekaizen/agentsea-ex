defmodule AgentSea.Core.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Supervises the short-lived Tasks that run an agent's tool calls, so a
      # crashing tool is isolated from the agent process.
      {Task.Supervisor, name: AgentSea.ToolTaskSup}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: AgentSea.Core.Supervisor)
  end
end
