Code.require_file("../../hex_deps.exs", __DIR__)

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
      description:
        "AgentSea ingest: a Broadway document ingestion pipeline (chunk, embed, store).",
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
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      AgentSea.HexDeps.sibling(:agentsea_embeddings),
      {:broadway, "~> 1.0"}
    ]
  end
end
