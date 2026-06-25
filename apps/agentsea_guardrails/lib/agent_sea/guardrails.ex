defmodule AgentSea.Guardrails do
  @moduledoc """
  Run a pipeline of `AgentSea.Guardrail`s over text. Apply it to user input
  before `AgentSea.Agent.run/3` and/or to the agent's output before returning:

      case AgentSea.Guardrails.run(user_input, [
             {AgentSea.Guardrail.MaxLength, max: 2000},
             {AgentSea.Guardrail.Blocklist, terms: ["ignore previous instructions"]},
             AgentSea.Guardrail.PIIRedactor
           ]) do
        {:ok, safe} -> AgentSea.Agent.run(agent, safe)
        {:block, {guardrail, reason}} -> {:error, {:blocked, guardrail, reason}}
      end

  Guardrails run in order. A `{:transform, _}` updates the content seen by later
  guardrails; the first `{:block, _}` short-circuits.
  """

  @type guardrail :: module() | {module(), keyword()}

  @spec run(String.t(), [guardrail()]) ::
          {:ok, String.t()} | {:block, {name :: String.t(), reason :: term()}}
  def run(content, guardrails) do
    Enum.reduce_while(guardrails, {:ok, content}, fn guardrail, {:ok, current} ->
      {module, opts} = normalize(guardrail)

      case module.check(current, opts) do
        :ok ->
          {:cont, {:ok, current}}

        {:transform, new} ->
          emit(module, :transform)
          {:cont, {:ok, new}}

        {:block, reason} ->
          emit(module, :block)
          {:halt, {:block, {module.name(), reason}}}
      end
    end)
  end

  defp normalize({module, opts}), do: {module, opts}
  defp normalize(module), do: {module, []}

  # Emit only the noteworthy outcomes (a transform or a block), so the dashboard
  # / any telemetry handler sees guardrail activity. A plain pass is silent.
  defp emit(module, outcome) do
    :telemetry.execute(
      [:agentsea, :guardrail, :stop],
      %{system_time: System.system_time()},
      %{guardrail: module.name(), outcome: outcome}
    )
  end
end
