Code.require_file("../../hex_deps.exs", __DIR__)

defmodule AgentSea.Web.MixProject do
  use Mix.Project

  def project do
    [
      app: :agentsea_web,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description:
        "AgentSea web: a Phoenix LiveView fleet dashboard and an OpenAI-compatible chat completions endpoint.",
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
      mod: {AgentSea.Web.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      AgentSea.HexDeps.sibling(:agentsea_core),
      AgentSea.HexDeps.sibling(:agentsea_gateway),
      {:phoenix, "~> 1.7.14"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:telemetry, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:bandit, "~> 1.5"},
      {:lazy_html, ">= 0.1.0", only: :test}
    ]
  end
end
