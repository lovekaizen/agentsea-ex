defmodule AgentSea.Voice.MixProject do
  use Mix.Project

  def project do
    [
      app: :agentsea_voice,
      version: "0.1.0",
      build_path: "../../_build",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      description:
        "AgentSea voice: text-to-speech and speech-to-text behaviours with OpenAI and ElevenLabs adapters.",
      package: [
        licenses: ["Apache-2.0"],
        maintainers: ["lovekaizen"],
        links: %{"GitHub" => "https://github.com/lovekaizen/agentsea-ex"}
      ],
      deps: deps()
    ] ++ shared_config()
  end

  # Use the umbrella's shared config when present; otherwise omit config_path
  # so Mix falls back to its default (a missing config is skipped). Keeps
  # per-app builds (e.g. `mix hex.build`) from hard-failing if the root
  # config/config.exs is absent.
  defp shared_config do
    path = "../../config/config.exs"
    if File.exists?(Path.expand(path, __DIR__)), do: [config_path: path], else: []
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
