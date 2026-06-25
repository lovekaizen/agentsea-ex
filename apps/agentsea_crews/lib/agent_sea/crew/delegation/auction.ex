defmodule AgentSea.Crew.Delegation.Auction do
  @moduledoc """
  Agents bid on the task; the best bid wins.

  Bids are collected as a **parallel `GenServer.call` fan-out** — the bidding
  window is literally the call timeout. Slow or dead bidders simply miss the
  window (`on_timeout: :kill_task`); there is no `Promise.race` and no leaked
  timers.

  Context options:

    * `:bidding_time_ms`    — per-bid timeout (default 5000)
    * `:minimum_bid`        — drop bids below this confidence (default 0.0)
    * `:selection_criteria` — `:confidence` (default) | `:fastest` | `:cheapest`
  """

  @behaviour AgentSea.Crew.Delegation
  alias AgentSea.Crew.Delegation.Result

  @default_bidding_ms 5_000

  @impl true
  def delegate(_task, [], _ctx), do: {:error, :no_agents}

  def delegate(task, agents, ctx) do
    bidding_ms = Map.get(ctx, :bidding_time_ms, @default_bidding_ms)
    minimum_bid = Map.get(ctx, :minimum_bid, 0.0)
    criteria = Map.get(ctx, :selection_criteria, :confidence)

    bids =
      agents
      |> Task.async_stream(
        fn agent -> {agent, AgentSea.Agent.bid(agent.pid, task)} end,
        timeout: bidding_ms,
        on_timeout: :kill_task,
        max_concurrency: max(length(agents), 1)
      )
      |> Enum.flat_map(fn
        {:ok, {agent, {:ok, bid}}} -> [{agent, bid}]
        # timed-out / crashed / failed bidders don't compete
        _ -> []
      end)
      |> Enum.filter(fn {_agent, bid} -> bid.confidence >= minimum_bid end)

    case pick(bids, criteria) do
      nil ->
        {:error, :no_bids}

      {agent, bid} ->
        {:ok,
         %Result{
           selected_agent: agent.name,
           confidence: bid.confidence,
           reason: "won auction (#{criteria}); confidence #{Float.round(bid.confidence, 2)}",
           alternatives:
             bids
             |> Enum.reject(fn {a, _} -> a.name == agent.name end)
             |> Enum.map(fn {a, _} -> a.name end)
         }}
    end
  end

  defp pick([], _criteria), do: nil
  defp pick(bids, :confidence), do: Enum.max_by(bids, fn {_a, b} -> b.confidence end)

  defp pick(bids, :fastest),
    do: Enum.min_by(bids, fn {_a, b} -> b.estimated_time || :infinity end)

  defp pick(bids, :cheapest),
    do: Enum.min_by(bids, fn {_a, b} -> b.estimated_cost || :infinity end)
end
