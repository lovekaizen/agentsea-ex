defmodule AgentSea.Crew.Delegation do
  @moduledoc """
  Strategy behaviour for assigning a task to an agent. Each strategy is a module
  implementing `c:delegate/3`; the coordinator selects one by config.
  """

  defmodule Result do
    @moduledoc "The outcome of a delegation decision."

    @enforce_keys [:selected_agent]
    defstruct [:selected_agent, :reason, :confidence, alternatives: [], decision_time_ms: 0]

    @type t :: %__MODULE__{
            selected_agent: term(),
            reason: String.t() | nil,
            confidence: float() | nil,
            alternatives: [term()],
            decision_time_ms: non_neg_integer()
          }
  end

  @typedoc "A candidate agent: its name, pid, and (optional) role."
  @type agent_ref :: %{
          required(:name) => term(),
          required(:pid) => pid() | nil,
          optional(:role) => AgentSea.Role.t() | nil
        }

  @typedoc "Strategy context, e.g. `:counter`, `:bidding_time_ms`, `:minimum_bid`, `:selection_criteria`."
  @type ctx :: map()

  @callback delegate(task :: term(), [agent_ref()], ctx()) ::
              {:ok, Result.t()} | {:error, term()}

  @doc "Run a delegation strategy, timing the decision."
  @spec select(module(), term(), [agent_ref()], ctx()) ::
          {:ok, Result.t()} | {:error, term()}
  def select(strategy, task, agents, ctx \\ %{}) do
    started = System.monotonic_time(:millisecond)

    case strategy.delegate(task, agents, ctx) do
      {:ok, %Result{} = result} ->
        {:ok, %{result | decision_time_ms: System.monotonic_time(:millisecond) - started}}

      other ->
        other
    end
  end
end
