defmodule AgentSea.Crew.Task do
  @moduledoc "A unit of work for a crew, with optional capability requirements and dependencies."

  @enforce_keys [:description]
  defstruct [
    :id,
    :description,
    :expected_output,
    required_capabilities: [],
    priority: :medium,
    depends_on: [],
    context: %{}
  ]

  @type priority :: :low | :medium | :high | :critical

  @type t :: %__MODULE__{
          id: String.t() | nil,
          description: String.t(),
          expected_output: String.t() | nil,
          required_capabilities: [String.t()],
          priority: priority(),
          depends_on: [String.t()],
          context: map()
        }

  @doc "Build a task, generating an id when one isn't supplied."
  @spec new(keyword() | map()) :: t()
  def new(attrs) do
    attrs = Map.new(attrs)
    struct!(__MODULE__, Map.put_new_lazy(attrs, :id, &gen_id/0))
  end

  @doc "Render the task as the input string given to an agent."
  @spec input(t()) :: String.t()
  def input(%__MODULE__{description: description, expected_output: nil}), do: description

  def input(%__MODULE__{description: description, expected_output: expected}),
    do: "#{description}\n\nExpected output: #{expected}"

  defp gen_id, do: "task_" <> Integer.to_string(System.unique_integer([:positive]))
end
