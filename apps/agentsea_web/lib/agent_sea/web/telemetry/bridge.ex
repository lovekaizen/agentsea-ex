defmodule AgentSea.Web.Telemetry.Bridge do
  @moduledoc """
  Forwards every `AgentSea.Telemetry` event onto `Phoenix.PubSub` so LiveViews
  (the dashboard) can render fleet activity in real time without any bespoke
  event bus.
  """

  @handler_id "agentsea-web-bridge"
  @topic "agentsea:events"

  @doc "The PubSub topic dashboard LiveViews subscribe to."
  def topic, do: @topic

  @doc "Attach the bridge to all AgentSea telemetry events."
  def attach do
    :telemetry.attach_many(
      @handler_id,
      AgentSea.Telemetry.events(),
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def detach, do: :telemetry.detach(@handler_id)

  @doc false
  def handle_event(event, measurements, metadata, _config) do
    message =
      {:agentsea_event,
       %{
         event: event,
         measurements: measurements,
         metadata: metadata,
         at: System.system_time(:millisecond)
       }}

    Phoenix.PubSub.broadcast(AgentSea.PubSub, @topic, message)
  end
end
