Code.require_file("../../hex_deps.exs", __DIR__)

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
      description:
        "AgentSea MCP: a Model Context Protocol client with stdio and streamable-HTTP transports.",
      package: [
        licenses: ["Apache-2.0"],
        maintainers: ["lovekaizen"],
        links: %{"GitHub" => "https://github.com/lovekaizen/agentsea-ex"}
      ],
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
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      AgentSea.HexDeps.sibling(:agentsea_core),
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"},
      {:mox, "~> 1.1", only: :test}
    ]
  end
end
