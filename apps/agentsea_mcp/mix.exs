defmodule AgentSea.MCP.MixProject do
  use Mix.Project

  def project do
    [
      app: :agentsea_mcp,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:agentsea_core, in_umbrella: true},
      {:jason, "~> 1.4"},
      {:mox, "~> 1.1", only: :test}
    ]
  end
end
