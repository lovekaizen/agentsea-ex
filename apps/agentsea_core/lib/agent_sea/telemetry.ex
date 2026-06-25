defmodule AgentSea.Telemetry do
  @moduledoc """
  Telemetry events emitted across AgentSea. Attach handlers — a Logger, a
  Prometheus exporter, or a Phoenix LiveView dashboard — to observe agent,
  provider, tool, and crew activity without any bespoke event bus.

  All events are under the `:agentsea` prefix.

  Span events (emit `:start`, `:stop`, and `:exception` via `:telemetry.span/3`):

    * `[:agentsea, :agent, :run, _]` — a full `AgentSea.Agent.run/3`
      * metadata: `%{name, model}`; `:stop` adds `%{outcome, stop_reason}`
    * `[:agentsea, :provider, :complete, _]` — one provider completion in the loop
      * metadata: `%{provider, model, name, iteration}`;
        `:stop` adds `%{outcome, stop_reason, input_tokens, output_tokens}`
    * `[:agentsea, :tool, :run, _]` — one tool execution
      * metadata: `%{tool, agent}`; `:stop` adds `%{outcome}`

  Discrete events (emit `:start` and `:stop` via `:telemetry.execute/3`):

    * `[:agentsea, :crew, :kickoff, :start | :stop]` — a crew run
      * metadata: `%{crew, task_count}`; `:stop` adds `%{success}`,
        measurements `%{duration}`
    * `[:agentsea, :crew, :task, :start | :stop]` — one crew task
      * metadata: `%{crew, task_id, agent}`; `:stop` carries `%{crew, task_id, outcome}`
    * `[:agentsea, :gateway, :route, :stop]` — a gateway routing decision
      * metadata: `%{provider, outcome}`; measurements `%{attempts, latency_ms}`
  """

  require Logger

  @spans [
    [:agentsea, :agent, :run],
    [:agentsea, :provider, :complete],
    [:agentsea, :tool, :run]
  ]

  @discrete [
    [:agentsea, :crew, :kickoff],
    [:agentsea, :crew, :task],
    [:agentsea, :gateway, :route]
  ]

  @doc "Every event name AgentSea may emit."
  @spec events() :: [[atom()]]
  def events do
    span_events = Enum.flat_map(@spans, &expand(&1, [:start, :stop, :exception]))
    discrete_events = Enum.flat_map(@discrete, &expand(&1, [:start, :stop]))
    span_events ++ discrete_events
  end

  defp expand(base, suffixes), do: Enum.map(suffixes, &(base ++ [&1]))

  @doc "Attach a Logger handler for all AgentSea events (handy in dev)."
  @spec attach_default_logger(Logger.level()) :: :ok | {:error, :already_exists}
  def attach_default_logger(level \\ :debug) do
    :telemetry.attach_many(
      "agentsea-default-logger",
      events(),
      &__MODULE__.handle_event/4,
      %{level: level}
    )
  end

  @doc false
  def handle_event(event, measurements, metadata, %{level: level}) do
    Logger.log(level, fn ->
      "#{Enum.join(event, ".")} #{inspect(measurements)} #{inspect(metadata)}"
    end)
  end
end
