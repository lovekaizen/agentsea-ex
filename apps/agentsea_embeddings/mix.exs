Code.require_file("../../hex_deps.exs", __DIR__)

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
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description:
        "AgentSea embeddings: embedder/vector-store behaviours, RAG, and in-memory/pgvector/Qdrant/Pinecone stores.",
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

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    # The in-memory store + hashing embedder are dependency-free; core is needed
    # for the retrieval tool, postgrex/jason for the pgvector store, and req for
    # the Qdrant store. Bumblebee is a drop-in embedder (see agentsea_bumblebee).
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      AgentSea.HexDeps.sibling(:agentsea_core),
      {:postgrex, "~> 0.17"},
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:mox, "~> 1.1", only: :test}
    ]
  end
end
