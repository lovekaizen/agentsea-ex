defmodule AgentSea.Web.DashboardLive do
  @moduledoc """
  Live dashboard of AgentSea activity. Subscribes to telemetry events forwarded
  over PubSub and renders running totals plus a feed of recent events.
  """

  use Phoenix.LiveView

  alias AgentSea.Web.Telemetry.Bridge

  @max_events 50

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(AgentSea.PubSub, Bridge.topic())

    {:ok,
     assign(socket,
       events: [],
       stats: %{runs: 0, tool_runs: 0, crews: 0, input_tokens: 0, output_tokens: 0, blocked: 0}
     )}
  end

  @impl true
  def handle_info({:agentsea_event, event}, socket) do
    {:noreply,
     socket
     |> update(:events, fn events -> Enum.take([event | events], @max_events) end)
     |> update(:stats, &update_stats(&1, event))}
  end

  defp update_stats(stats, %{event: event, metadata: metadata}) do
    case event do
      [:agentsea, :agent, :run, :stop] ->
        Map.update!(stats, :runs, &(&1 + 1))

      [:agentsea, :tool, :run, :stop] ->
        Map.update!(stats, :tool_runs, &(&1 + 1))

      [:agentsea, :crew, :kickoff, :stop] ->
        Map.update!(stats, :crews, &(&1 + 1))

      [:agentsea, :provider, :complete, :stop] ->
        stats
        |> Map.update!(:input_tokens, &(&1 + Map.get(metadata, :input_tokens, 0)))
        |> Map.update!(:output_tokens, &(&1 + Map.get(metadata, :output_tokens, 0)))

      [:agentsea, :guardrail, :stop] ->
        if Map.get(metadata, :outcome) == :block,
          do: Map.update!(stats, :blocked, &(&1 + 1)),
          else: stats

      _ ->
        stats
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="dashboard">
      <h1>AgentSea Dashboard</h1>

      <div id="stats">
        <span id="stat-runs">Agent runs: {@stats.runs}</span>
        <span id="stat-tools">Tool runs: {@stats.tool_runs}</span>
        <span id="stat-crews">Crews: {@stats.crews}</span>
        <span id="stat-tokens">Tokens: {@stats.input_tokens + @stats.output_tokens}</span>
        <span id="stat-blocked">Guardrail blocks: {@stats.blocked}</span>
      </div>

      <ul id="events">
        <li :for={event <- @events} class="event">
          <span class="event-name">{Enum.join(event.event, ".")}</span>
          <span class="event-meta">{describe(event.metadata)}</span>
        </li>
      </ul>
    </div>
    """
  end

  defp describe(metadata) do
    metadata
    |> Map.drop([:telemetry_span_context])
    |> Enum.map_join(" ", fn {k, v} -> "#{k}=#{inspect(v)}" end)
  end
end
