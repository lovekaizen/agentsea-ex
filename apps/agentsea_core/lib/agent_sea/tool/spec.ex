defmodule AgentSea.Tool.Spec do
  @moduledoc """
  A runtime (function-backed) tool, for tools that can't be compile-time modules
  — e.g. ad-hoc closures or tools discovered dynamically (MCP). An agent accepts
  these alongside `AgentSea.Tool` modules in its `tools` list.
  """

  @enforce_keys [:name, :run]
  defstruct [:name, :description, :run, schema: []]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t() | nil,
          schema: keyword(),
          run: (map(), map() -> {:ok, term()} | {:error, term()})
        }
end
