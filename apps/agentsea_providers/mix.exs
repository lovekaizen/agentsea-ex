defmodule AgentSea.Providers.MixProject do
  use Mix.Project

  def project do
    [
      app: :agentsea_providers,
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
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"}
    ]
  end
end
