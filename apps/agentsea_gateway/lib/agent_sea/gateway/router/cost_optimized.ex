defmodule AgentSea.Gateway.Router.CostOptimized do
  @moduledoc "Orders candidates cheapest-model-first using `AgentSea.ModelPricing`."
  @behaviour AgentSea.Gateway.Router

  @impl true
  def order(candidates, _ctx) do
    Enum.sort_by(candidates, &AgentSea.ModelPricing.weight(&1.model))
  end
end
