defmodule AgentSea.Core.MixProject do
  use Mix.Project

  def project do
    [
      app: :agentsea_core,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description:
        "AgentSea core: the agent GenServer, the agentic run loop, and the Provider/Tool/Memory behaviours.",
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
      mod: {AgentSea.Core.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:nimble_options, "~> 1.1"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.0"},
      {:mox, "~> 1.1", only: :test}
    ]
  end
end
