defmodule AgentSea.Evaluate.Metric.LLMJudge do
  @moduledoc """
  Uses an LLM to score an output against a rubric — "LLM-as-judge". Runs over any
  `AgentSea.Provider` (so it can go through the gateway).

  Options:
    * `:provider`  — `{module, opts}` (required)
    * `:model`     — model id (or in the provider opts)
    * `:rubric`    — grading instructions (default: relevance/correctness)
    * `:threshold` — pass cutoff in [0,1] (default 0.5)
  """

  @behaviour AgentSea.Evaluate.Metric

  @default_rubric "Rate how well the response satisfies the request and matches the expected answer."

  @impl true
  def name, do: "llm_judge"

  @impl true
  def evaluate(example, opts) do
    {provider_mod, provider_opts} = Keyword.fetch!(opts, :provider)
    model = Keyword.get(opts, :model) || Keyword.get(provider_opts, :model)
    threshold = Keyword.get(opts, :threshold, 0.5)

    messages = judge_messages(example, Keyword.get(opts, :rubric, @default_rubric))

    case provider_mod.complete(messages, Keyword.put(provider_opts, :model, model)) do
      {:ok, response} ->
        score = parse_score(response.content)
        %{score: score, passed: score >= threshold}

      {:error, _reason} ->
        %{score: 0.0, passed: false}
    end
  end

  defp judge_messages(example, rubric) do
    system =
      "You are a strict evaluator. #{rubric} " <>
        "Respond with ONLY a single number between 0 and 1 (1 = perfect)."

    user =
      """
      Input: #{Map.get(example, :input, "")}
      Expected: #{inspect(Map.get(example, :expected))}
      Response: #{example.output}

      Score:
      """

    [%{role: :system, content: system}, %{role: :user, content: user}]
  end

  defp parse_score(content) do
    case Regex.run(~r/-?\d+(?:\.\d+)?/, content) do
      [number] ->
        case Float.parse(number) do
          {value, _rest} -> value |> max(0.0) |> min(1.0)
          :error -> 0.0
        end

      _ ->
        0.0
    end
  end
end
