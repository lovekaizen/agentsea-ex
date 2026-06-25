defmodule AgentSea.Gateway.Router.Failover do
  @moduledoc "Tries candidates in their configured (priority) order."
  @behaviour AgentSea.Gateway.Router

  @impl true
  def order(candidates, _ctx), do: candidates
end
