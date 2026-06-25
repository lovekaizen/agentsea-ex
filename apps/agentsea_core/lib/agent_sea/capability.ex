defmodule AgentSea.Capability do
  @moduledoc """
  A named capability an agent has, with a proficiency level. Capability matching
  is pure: given an agent's capabilities and the names a task requires, compute
  which are matched/missing, an aggregate score in `[0, 1]`, and whether the
  agent can execute the task at all.
  """

  @enforce_keys [:name]
  defstruct [:name, :description, proficiency: :intermediate, keywords: []]

  @type proficiency :: :novice | :intermediate | :expert | :master

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t() | nil,
          proficiency: proficiency(),
          keywords: [String.t()]
        }

  @type match :: %{
          matched: [String.t()],
          missing: [String.t()],
          score: float(),
          can_execute: boolean()
        }

  @scores %{novice: 0.25, intermediate: 0.5, expert: 0.75, master: 1.0}

  @doc "Numeric weight for a capability's proficiency."
  @spec proficiency_score(t()) :: float()
  def proficiency_score(%__MODULE__{proficiency: p}), do: Map.get(@scores, p, 0.5)

  @doc """
  Match agent capabilities against the capability names a task requires.

  With no required capabilities, the score reflects the agent's overall
  proficiency and `can_execute` is true. Otherwise the score is coverage
  (fraction of required capabilities present) times the average proficiency of
  the matched ones, and `can_execute` is true only when nothing is missing.
  """
  @spec match([t()], [String.t()]) :: match()
  def match(agent_capabilities, [] = _required) do
    %{matched: [], missing: [], score: avg_proficiency(agent_capabilities), can_execute: true}
  end

  def match(agent_capabilities, required_names) do
    have = Map.new(agent_capabilities, &{&1.name, &1})
    required = Enum.uniq(required_names)
    {matched, missing} = Enum.split_with(required, &Map.has_key?(have, &1))

    coverage = length(matched) / length(required)
    avg = matched |> Enum.map(&proficiency_score(have[&1])) |> average(0.0)

    %{
      matched: matched,
      missing: missing,
      score: coverage * avg,
      can_execute: missing == []
    }
  end

  defp avg_proficiency([]), do: 0.0
  defp avg_proficiency(caps), do: caps |> Enum.map(&proficiency_score/1) |> average(0.0)

  defp average([], default), do: default
  defp average(list, _default), do: Enum.sum(list) / length(list)
end
