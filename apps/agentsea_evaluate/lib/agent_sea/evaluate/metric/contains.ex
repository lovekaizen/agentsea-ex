defmodule AgentSea.Evaluate.Metric.Contains do
  @moduledoc "Scores 1.0 when the output contains the expected value (case-insensitive substring)."
  @behaviour AgentSea.Evaluate.Metric

  @impl true
  def name, do: "contains"

  @impl true
  def evaluate(%{output: output} = example, _opts) do
    expected = example |> Map.get(:expected) |> to_string() |> String.downcase()
    score = if String.contains?(String.downcase(output), expected), do: 1.0, else: 0.0
    %{score: score, passed: score == 1.0}
  end
end
