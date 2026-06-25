Code.require_file("../../hex_deps.exs", __DIR__)

defmodule AgentSea.Guardrails.MixProject do
  use Mix.Project

  def project do
    [
      app: :agentsea_guardrails,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      description:
        "AgentSea guardrails: an input/output validation pipeline with rule-based and LLM moderation guardrails.",
      package: [
        licenses: ["Apache-2.0"],
        maintainers: ["Michael Bello"],
        links: %{"GitHub" => "https://github.com/lovekaizen/agentsea-ex"}
      ],
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      AgentSea.HexDeps.sibling(:agentsea_core),
      {:mox, "~> 1.1", only: :test}
    ]
  end
end
