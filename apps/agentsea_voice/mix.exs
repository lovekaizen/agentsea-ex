defmodule AgentSea.Voice.MixProject do
  use Mix.Project

  def project do
    [
      app: :agentsea_voice,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      description:
        "AgentSea voice: text-to-speech and speech-to-text behaviours with OpenAI and ElevenLabs adapters.",
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
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"}
    ]
  end
end
