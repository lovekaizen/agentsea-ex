Code.require_file("../../hex_deps.exs", __DIR__)

defmodule AgentSea.Crews.MixProject do
  use Mix.Project

  def project do
    [
      app: :agentsea_crews,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description:
        "AgentSea crews: multi-agent coordination with delegation strategies and a gen_statem task-DAG coordinator.",
      package: [
        licenses: ["Apache-2.0"],
        maintainers: ["Michael Bello"],
        links: %{"GitHub" => "https://github.com/lovekaizen/agentsea-ex"}
      ],
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {AgentSea.Crews.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      AgentSea.HexDeps.sibling(:agentsea_core),
      {:telemetry, "~> 1.0"}
    ]
  end
end
