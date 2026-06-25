defmodule AgentSea.Crew.Delegation.BestMatch do
  @moduledoc """
  Selects the agent whose role capabilities best fit the task. Prefers agents
  that can fully execute the task, breaking ties by capability score. Pure — uses
  the role on each `agent_ref`, no process calls.
  """

  @behaviour AgentSea.Crew.Delegation

  alias AgentSea.Capability
  alias AgentSea.Crew.Delegation.Result

  @impl true
  def delegate(_task, [], _ctx), do: {:error, :no_agents}

  def delegate(task, agents, _ctx) do
    required = Map.get(task, :required_capabilities, [])

    ranked =
      agents
      |> Enum.map(fn agent -> {agent, Capability.match(role_capabilities(agent), required)} end)
      # can_execute (true sorts after false) then score, both descending
      |> Enum.sort_by(fn {_agent, m} -> {m.can_execute, m.score} end, :desc)

    [{best, match} | rest] = ranked

    {:ok,
     %Result{
       selected_agent: best.name,
       confidence: match.score,
       reason: "best capability match (score #{Float.round(match.score, 2)})",
       alternatives: Enum.map(rest, fn {agent, _m} -> agent.name end)
     }}
  end

  defp role_capabilities(%{role: %AgentSea.Role{capabilities: caps}}), do: caps
  defp role_capabilities(_), do: []
end
