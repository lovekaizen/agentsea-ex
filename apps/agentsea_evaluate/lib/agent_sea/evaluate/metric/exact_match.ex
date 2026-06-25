defmodule AgentSea.Evaluate.Metric.ExactMatch do
  @moduledoc "Scores 1.0 when the output equals the expected value (trimmed, case-insensitive)."
  @behaviour AgentSea.Evaluate.Metric

  @impl true
  def name, do: "exact_match"

  @impl true
  def evaluate(%{output: output} = example, _opts) do
    expected = Map.get(example, :expected)
    score = if normalize(output) == normalize(expected), do: 1.0, else: 0.0
    %{score: score, passed: score == 1.0}
  end

  defp normalize(value), do: value |> to_string() |> String.trim() |> String.downcase()
end
