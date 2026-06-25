defmodule AgentSea.Bid do
  @moduledoc """
  An agent's bid on a task, produced by `AgentSea.Agent.bid/2`. Used by the
  auction delegation strategy. `estimated_cost` combines the model's price tier
  with the estimated effort, so the `:cheapest` criterion can distinguish a
  cheap-but-slower model from an expensive-but-faster one.
  """

  @enforce_keys [:agent_name, :confidence]
  defstruct [
    :agent_name,
    :task_id,
    :confidence,
    :estimated_time,
    :estimated_cost,
    :reasoning,
    capabilities: []
  ]

  @type t :: %__MODULE__{
          agent_name: term(),
          task_id: term() | nil,
          confidence: float(),
          estimated_time: number() | nil,
          estimated_cost: number() | nil,
          reasoning: String.t() | nil,
          capabilities: [String.t()]
        }
end
