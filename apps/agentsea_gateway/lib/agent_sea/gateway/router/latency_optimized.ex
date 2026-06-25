defmodule AgentSea.Gateway.Router.LatencyOptimized do
  @moduledoc """
  Orders candidates by lowest observed latency (from gateway health). Candidates
  with no recorded latency yet are tried last.
  """
  @behaviour AgentSea.Gateway.Router

  @unknown 1_000_000

  @impl true
  def order(candidates, ctx) do
    health = Map.get(ctx, :health, %{})

    Enum.sort_by(candidates, fn candidate ->
      case health[candidate.name] do
        %{latency_ms: ms} when is_integer(ms) -> ms
        _ -> @unknown
      end
    end)
  end
end
