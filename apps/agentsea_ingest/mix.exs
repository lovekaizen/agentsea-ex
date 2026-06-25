defmodule AgentSea.Ingest.MixProject do
  use Mix.Project

  def project do
    [
      app: :agentsea_ingest,
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
      {:agentsea_embeddings, in_umbrella: true},
      {:broadway, "~> 1.0"}
    ]
  end
end
