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
      {:agentsea_core, in_umbrella: true},
      # Pinned to the 3.12 line (decimal ~> 2.0) so it co-resolves with bumblebee,
      # whose progress_bar requires decimal ~> 2.0. Ecto 3.13+ moved to decimal 3.0.
      {:ecto, "~> 3.12.0"},
      {:jason, "~> 1.4"},
      {:mox, "~> 1.1", only: :test}
    ]
  end
end
