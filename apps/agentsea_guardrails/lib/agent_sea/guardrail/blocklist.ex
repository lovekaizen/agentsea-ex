defmodule AgentSea.Guardrail.Blocklist do
  @moduledoc """
  Blocks content containing any banned `:terms` (case-insensitive substrings) —
  handy for prompt-injection phrases or disallowed topics.
  """
  @behaviour AgentSea.Guardrail

  @impl true
  def name, do: "blocklist"

  @impl true
  def check(content, opts) do
    terms = Keyword.get(opts, :terms, [])
    downcased = String.downcase(content)

    case Enum.find(terms, fn term -> String.contains?(downcased, String.downcase(term)) end) do
      nil -> :ok
      term -> {:block, {:blocked_term, term}}
    end
  end
end
