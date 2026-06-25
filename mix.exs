defmodule AgentSea.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      name: "AgentSea",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs()
    ]
  end

  defp dialyzer do
    [
      plt_local_path: "priv/plts",
      plt_core_path: "priv/plts",
      plt_add_apps: [:mix, :ex_unit],
      flags: [:error_handling, :extra_return, :missing_return]
    ]
  end

  defp docs do
    [
      name: "AgentSea",
      source_url: "https://github.com/lovekaizen/agentsea",
      extras: ["README.md", "docs/DESIGN.md"],
      main: "readme"
    ]
  end

  # Dependencies listed here are available only for this umbrella project and
  # cannot be accessed from applications inside the apps/ folder.
  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
