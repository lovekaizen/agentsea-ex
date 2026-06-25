defmodule AgentSea.Provider do
  @moduledoc """
  A chat-completion backend (Anthropic, OpenAI, a local model, …).

  Every LLM integration implements this behaviour. Streaming is optional and,
  where supported, returns a lazy `Stream` of normalized chunks built from an
  SSE body — there is no async-generator plumbing.
  """

  @typedoc "A single conversation message. `role` is required; extra keys (e.g. `tool_calls`, `tool_call_id`) are allowed."
  @type message :: %{
          required(:role) => :system | :user | :assistant | :tool,
          required(:content) => term(),
          optional(atom()) => term()
        }

  @typedoc "Provider options (model, api_key, system_prompt, tools, …)."
  @type opts :: keyword()

  @typedoc "A streamed event from `c:stream/2`."
  @type stream_event ::
          {:content, String.t()}
          | {:thinking, String.t()}
          | {:tool_call, map()}
          | :done

  @doc "Run a single (non-streaming) completion."
  @callback complete([message()], opts()) ::
              {:ok, AgentSea.Response.t()} | {:error, term()}

  @doc "Run a streaming completion, returning a lazy stream of `t:stream_event/0`."
  @callback stream([message()], opts()) :: Enumerable.t()

  @doc "Static capabilities for a model id; `nil` for unknown models."
  @callback model_info(model :: String.t()) :: AgentSea.ModelInfo.t() | nil

  @optional_callbacks stream: 2
end
