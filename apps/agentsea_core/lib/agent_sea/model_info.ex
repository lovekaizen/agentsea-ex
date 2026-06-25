defmodule AgentSea.ModelInfo do
  @moduledoc "Static capabilities of a model, used by the gateway and for validation."

  defstruct context_window: nil,
            max_output_tokens: nil,
            tools: false,
            vision: false,
            thinking: false,
            effort: []

  @type t :: %__MODULE__{
          context_window: pos_integer() | nil,
          max_output_tokens: pos_integer() | nil,
          tools: boolean(),
          vision: boolean(),
          thinking: boolean(),
          effort: [atom()]
        }
end
