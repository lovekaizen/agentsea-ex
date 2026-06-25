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
        :ok -> {:cont, {:ok, current}}
        {:transform, new} -> {:cont, {:ok, new}}
        {:block, reason} -> {:halt, {:block, {module.name(), reason}}}
      end
    end)
  end

  defp normalize({module, opts}), do: {module, opts}
  defp normalize(module), do: {module, []}
end
