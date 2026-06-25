defmodule AgentSea.Embeddings.MixProject do
  use Mix.Project

  def project do
    [
      app: :agentsea_embeddings,
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
    # Dependency-free by design: the in-memory store + hashing embedder need
    # nothing extra. Bumblebee/Nx and pgvector are future drop-in adapters.
    []
  end
end
