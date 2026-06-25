defmodule AgentSea.Web.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # Forward AgentSea telemetry to PubSub for the LiveView dashboard.
    AgentSea.Web.Telemetry.Bridge.attach()

    children = [
      {Phoenix.PubSub, name: AgentSea.PubSub},
      AgentSea.Web.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: AgentSea.Web.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    AgentSea.Web.Endpoint.config_change(changed, removed)
    :ok
  end
end
