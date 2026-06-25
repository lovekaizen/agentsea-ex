defmodule AgentSea.Evaluate.Metric do
  @moduledoc """
  A scoring metric. Given an example (the `:output` under test, plus optional
  `:input`/`:expected`), it returns a score in `[0, 1]` and a pass/fail. Built-in
  metrics: `ExactMatch`, `Contains`, and `LLMJudge` (provider-backed).
  """

  @type example :: %{
          optional(:id) => term(),
          optional(:input) => String.t(),
          optional(:expected) => term(),
          required(:output) => String.t()
        }

  @type result :: %{score: float(), passed: boolean()}

  @callback name() :: String.t()
  @callback evaluate(example(), opts :: keyword()) :: result()
end
