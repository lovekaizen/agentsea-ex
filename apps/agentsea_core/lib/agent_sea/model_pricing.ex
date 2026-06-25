defmodule AgentSea.ModelPricing do
  @moduledoc """
  Coarse relative price tiers for models (not exact pricing) — enough for the
  auction's `:cheapest` bid and the gateway's cost-optimized routing to prefer
  cheaper models. Higher weight = pricier. For precise costs, track usage tokens
  against a real pricing table.
  """

  @doc "Relative price weight for a model id."
  @spec weight(String.t() | nil) :: float()
  def weight(model) do
    m = String.downcase(model || "")

    cond do
      contains_any?(m, ["opus", "gpt-5", "o3"]) -> 5.0
      contains_any?(m, ["sonnet", "gpt-4"]) -> 3.0
      contains_any?(m, ["haiku", "mini", "flash", "llama", "mistral"]) -> 1.0
      true -> 3.0
    end
  end

  defp contains_any?(string, substrings),
    do: Enum.any?(substrings, &String.contains?(string, &1))
end
