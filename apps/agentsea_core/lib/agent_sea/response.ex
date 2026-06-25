defmodule AgentSea.Response do
  @moduledoc "A normalized provider response."

  defstruct content: "",
            stop_reason: :stop,
            usage: %{input_tokens: 0, output_tokens: 0},
            tool_calls: [],
            raw: nil

  @type stop_reason :: :stop | :tool_use | :length | :error

  @type t :: %__MODULE__{
          content: String.t(),
          stop_reason: stop_reason(),
          usage: %{input_tokens: non_neg_integer(), output_tokens: non_neg_integer()},
          tool_calls: [AgentSea.ToolCall.t()],
          raw: term()
        }
end
