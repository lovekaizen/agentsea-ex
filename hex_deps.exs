defmodule AgentSea.HexDeps do
  @moduledoc """
  Resolves sibling umbrella apps as dependencies.

  In the umbrella, sibling apps resolve locally (`in_umbrella: true`) for
  dev/test. But Hex packages can only depend on *published* packages, so when
  publishing (`HEX_PUBLISH=1`) the same deps are expressed as version
  requirements instead. See `docs/PUBLISHING.md`.
  """

  # Keep in sync with the apps' `version:` (they share one version).
  @version "0.1.0"

  @doc "A sibling umbrella app dependency, publish-aware."
  def sibling(app) do
    if publishing?() do
      {app, "~> #{@version}"}
    else
      {app, in_umbrella: true}
    end
  end

  defp publishing?, do: System.get_env("HEX_PUBLISH") in ["1", "true"]
end
