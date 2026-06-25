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

  scope "/", AgentSea.Web do
    pipe_through :browser

    live "/", DashboardLive, :index
  end
end
