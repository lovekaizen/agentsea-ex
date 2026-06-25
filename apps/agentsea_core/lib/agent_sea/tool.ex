defmodule AgentSea.Tool do
  @moduledoc """
  A callable tool. A tool is a *module* implementing this behaviour —
  introspectable, testable, and supervisable. The parameter schema is a
  `NimbleOptions` keyword spec (not Zod), used both to validate calls and to
  advertise the tool to providers.
  """

  @doc "Unique tool name as seen by the model."
  @callback name() :: String.t()

  @doc "Human/model-readable description of what the tool does."
  @callback description() :: String.t()

  @doc "NimbleOptions schema describing the tool's parameters."
  @callback schema() :: keyword()

  @doc "Execute the tool with validated params and an execution context."
  @callback run(params :: map(), ctx :: map()) :: {:ok, term()} | {:error, term()}

  @doc "Whether a human must approve before execution (HITL). Defaults to false."
  @callback needs_approval?() :: boolean()

  @optional_callbacks needs_approval?: 0
end
