defmodule AgentSea.Role do
  @moduledoc "An agent's role: its capabilities, system prompt, goals and delegation policy."

  @enforce_keys [:name]
  defstruct [
    :name,
    :description,
    :system_prompt,
    :backstory,
    capabilities: [],
    goals: [],
    constraints: [],
    can_delegate: true,
    can_receive_delegation: true,
    max_concurrent_tasks: 1
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t() | nil,
          system_prompt: String.t() | nil,
          backstory: String.t() | nil,
          capabilities: [AgentSea.Capability.t()],
          goals: [String.t()],
          constraints: [String.t()],
          can_delegate: boolean(),
          can_receive_delegation: boolean(),
          max_concurrent_tasks: pos_integer()
        }
end
