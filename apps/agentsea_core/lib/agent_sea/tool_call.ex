defmodule AgentSea.ToolCall do
  @moduledoc "A tool invocation requested by the model."

  @enforce_keys [:name]
  defstruct [:id, :name, arguments: %{}]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t(),
          arguments: map()
        }
end
