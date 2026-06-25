defmodule AgentSea.Evaluate do
  @moduledoc """
  Run scoring metrics over a dataset, concurrently, and aggregate the results.

  Examples are evaluated in parallel with `Task.async_stream` (concurrency is a
  setting, not hand-rolled). Each metric is `{module, opts}` (or just `module`).

  ## Example

      dataset = [
        %{id: 1, input: "capital of France?", output: "Paris", expected: "Paris"},
        %{id: 2, input: "capital of France?", output: "London", expected: "Paris"}
      ]

      %{summary: summary} =
        AgentSea.Evaluate.run(dataset, [AgentSea.Evaluate.Metric.ExactMatch])

      summary["exact_match"].pass_rate  #=> 0.5
  """

  @type metric :: module() | {module(), keyword()}

  @type result :: %{id: term() | nil, metrics: %{String.t() => AgentSea.Evaluate.Metric.result()}}

  @spec run([AgentSea.Evaluate.Metric.example()], [metric()], keyword()) ::
          %{results: [result()], summary: map()}
  def run(examples, metrics, opts \\ []) do
    metrics = Enum.map(metrics, &normalize_metric/1)
    concurrency = Keyword.get(opts, :concurrency, System.schedulers_online())
    timeout = Keyword.get(opts, :timeout, 30_000)

    results =
      examples
      |> Task.async_stream(&evaluate_example(&1, metrics),
        max_concurrency: concurrency,
        timeout: timeout,
        ordered: true
      )
      |> Enum.map(fn {:ok, result} -> result end)

    %{results: results, summary: summarize(results, metrics)}
  end

  defp normalize_metric({module, opts}), do: {module, opts}
  defp normalize_metric(module), do: {module, []}

  defp evaluate_example(example, metrics) do
    scored =
      Map.new(metrics, fn {module, opts} ->
        {module.name(), module.evaluate(example, opts)}
      end)

    %{id: Map.get(example, :id), metrics: scored}
  end

  defp summarize(results, metrics) do
    for {module, _opts} <- metrics, into: %{} do
      name = module.name()
      scores = Enum.map(results, fn r -> r.metrics[name].score end)
      passes = Enum.count(results, fn r -> r.metrics[name].passed end)
      n = length(results)

      {name,
       %{
         mean_score: mean(scores),
         pass_rate: if(n > 0, do: passes / n, else: 0.0),
         count: n
       }}
    end
  end

  defp mean([]), do: 0.0
  defp mean(scores), do: Enum.sum(scores) / length(scores)
end
