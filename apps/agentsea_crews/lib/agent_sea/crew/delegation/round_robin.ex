defmodule AgentSea.Crew.Delegation.RoundRobin do
  @moduledoc """
  Cycles through agents by position. The position is supplied via `ctx.counter`
  (the coordinator owns and advances it), keeping the strategy pure.
  """

  @behaviour AgentSea.Crew.Delegation
  alias AgentSea.Crew.Delegation.Result

  @impl true
  def delegate(_task, [], _ctx), do: {:error, :no_agents}

  def delegate(_task, agents, ctx) do
    position = rem(Map.get(ctx, :counter, 0), length(agents))
    selected = Enum.at(agents, position)

    {:ok,
     %Result{
       selected_agent: selected.name,
       confidence: 1.0,
       reason: "round-robin position #{position}",
       alternatives: agents |> List.delete_at(position) |> Enum.map(& &1.name)
     }}
  end
end
