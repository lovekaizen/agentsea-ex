defmodule AgentSea.Gateway.Router.RoundRobin do
  @moduledoc "Rotates the candidate order by a counter so load spreads across providers."
  @behaviour AgentSea.Gateway.Router

  @impl true
  def order([], _ctx), do: []

  def order(candidates, ctx) do
    offset = rem(Map.get(ctx, :counter, 0), length(candidates))
    {head, tail} = Enum.split(candidates, offset)
    tail ++ head
  end
end
