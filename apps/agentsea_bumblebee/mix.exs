Code.require_file("../../hex_deps.exs", __DIR__)

defmodule AgentSea.Bumblebee.MixProject do
  use Mix.Project

  def project do
    [
      app: :agentsea_bumblebee,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      description:
        "AgentSea Bumblebee: in-process Hugging Face embeddings and Whisper speech-to-text via Bumblebee and Nx.",
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
      AgentSea.HexDeps.sibling(:agentsea_embeddings),
      AgentSea.HexDeps.sibling(:agentsea_voice),
      {:bumblebee, "~> 0.6"},
      {:nx, "~> 0.9"}
    ]
  end
end
