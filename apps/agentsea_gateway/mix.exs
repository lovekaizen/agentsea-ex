defmodule AgentSea.Gateway.MixProject do
  use Mix.Project

  def project do
    [
      app: :agentsea_gateway,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :fuse]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:agentsea_core, in_umbrella: true},
      {:fuse, "~> 2.5"},
      {:telemetry, "~> 1.0"}
    ]
  end
end
