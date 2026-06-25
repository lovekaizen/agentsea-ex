defmodule AgentSea.Web.Endpoint do
  use Phoenix.Endpoint, otp_app: :agentsea_web

  @session_options [
    store: :cookie,
    key: "_agentsea_web_key",
    signing_salt: "AgentSeaWeb",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  plug Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["*/*"],
    json_decoder: Jason

  plug Plug.Session, @session_options
  plug AgentSea.Web.Router
end
