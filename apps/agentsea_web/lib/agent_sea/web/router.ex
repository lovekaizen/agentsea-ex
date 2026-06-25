defmodule AgentSea.Web.Router do
  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :put_root_layout, html: {AgentSea.Web.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", AgentSea.Web do
    pipe_through :browser

    live "/", DashboardLive, :index
  end

  # OpenAI-compatible API served through the gateway.
  scope "/v1", AgentSea.Web do
    pipe_through :api

    post "/chat/completions", ChatController, :create
  end
end
