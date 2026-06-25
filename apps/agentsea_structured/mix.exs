Code.require_file("../../hex_deps.exs", __DIR__)

defmodule AgentSea.Structured.MixProject do
  use Mix.Project

  def project do
    [
      app: :agentsea_structured,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description:
        "AgentSea structured output: extract validated Ecto structs from an LLM, with validation retry.",
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

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      AgentSea.HexDeps.sibling(:agentsea_core),
      # Pinned to the 3.12 line (decimal ~> 2.0) so it co-resolves with bumblebee,
      # whose progress_bar requires decimal ~> 2.0. Ecto 3.13+ moved to decimal 3.0.
      {:ecto, "~> 3.12.0"},
      {:jason, "~> 1.4"},
      {:mox, "~> 1.1", only: :test}
    ]
  end
end
