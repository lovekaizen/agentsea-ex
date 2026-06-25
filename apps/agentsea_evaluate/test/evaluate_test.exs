defmodule AgentSea.EvaluateTest do
  use ExUnit.Case, async: true

  alias AgentSea.Evaluate
  alias AgentSea.Evaluate.Metric.{ExactMatch, Contains}

  test "aggregates pass rate and mean score across the dataset" do
    dataset = [
      %{id: 1, output: "Paris", expected: "Paris"},
      %{id: 2, output: "London", expected: "Paris"},
      %{id: 3, output: "paris", expected: "Paris"}
    ]

    %{results: results, summary: summary} = Evaluate.run(dataset, [ExactMatch])

    assert length(results) == 3
    # ids 1 and 3 match (case/trim-insensitive), id 2 doesn't.
    assert summary["exact_match"].count == 3
    assert_in_delta summary["exact_match"].pass_rate, 2 / 3, 1.0e-9
    assert_in_delta summary["exact_match"].mean_score, 2 / 3, 1.0e-9
  end

  test "runs multiple metrics per example" do
    dataset = [%{id: 1, output: "The capital is Paris.", expected: "Paris"}]

    %{summary: summary} = Evaluate.run(dataset, [ExactMatch, Contains])

    # Exact match fails (extra words) but Contains passes.
    assert summary["exact_match"].pass_rate == 0.0
    assert summary["contains"].pass_rate == 1.0
  end

  test "preserves example order and ids in results" do
    dataset = for i <- 1..5, do: %{id: i, output: "x", expected: "x"}
    %{results: results} = Evaluate.run(dataset, [ExactMatch], concurrency: 2)
    assert Enum.map(results, & &1.id) == [1, 2, 3, 4, 5]
  end

  test "handles an empty dataset" do
    %{results: results, summary: summary} = Evaluate.run([], [ExactMatch])
    assert results == []
    assert summary["exact_match"] == %{mean_score: 0.0, pass_rate: 0.0, count: 0}
  end
end
