import Config

config :phoenix, :json_library, Jason

# Dashboard endpoint. `server: false` by default — flip to true (and pick a
# port) to actually serve the dashboard; tests drive it in-process.
config :agentsea_web, AgentSea.Web.Endpoint,
  url: [host: "localhost"],
  secret_key_base: String.duplicate("agentsea_dev_secret_key_base_0123456789", 2),
  live_view: [signing_salt: "AgentSeaLV"],
  pubsub_server: AgentSea.PubSub,
  render_errors: [formats: [html: AgentSea.Web.ErrorHTML], layout: false],
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: false

if config_env() == :test do
  config :logger, level: :warning
end
