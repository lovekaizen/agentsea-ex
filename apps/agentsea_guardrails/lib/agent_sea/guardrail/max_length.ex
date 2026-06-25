defmodule AgentSea.Guardrail.MaxLength do
  @moduledoc "Blocks content longer than `:max` characters."
  @behaviour AgentSea.Guardrail

  @impl true
  def name, do: "max_length"

  @impl true
  def check(content, opts) do
    max = Keyword.fetch!(opts, :max)
    length = String.length(content)

    if length > max do
      {:block, {:too_long, length, max}}
    else
      :ok
    end
  end
end
