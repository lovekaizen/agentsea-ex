defmodule AgentSea.Agent do
  @moduledoc """
  An agent is a `GenServer` that owns its conversation state and runs the
  agentic loop: call the provider → if it requests tools, run them concurrently
  and feed the results back → repeat until the model answers or `max_iterations`
  is hit.

  Dependencies (provider, tools) are resolved from the `Config` struct, not
  injected via a constructor. A tool that raises is isolated by a supervised
  Task and folded into an `{:error, _}` result fed back to the model — the agent
  process never dies for a tool fault.
  """

  use GenServer

  alias AgentSea.{Response, ToolCall}

  defmodule Config do
    @moduledoc "Static configuration for an `AgentSea.Agent`."

    @enforce_keys [:name, :model, :provider]
    defstruct [
      :name,
      :description,
      :model,
      # {provider_module, provider_opts}
      :provider,
      :system_prompt,
      tools: [],
      temperature: nil,
      max_tokens: nil,
      max_iterations: 10,
      # Claude-specific, passed through to the provider:
      thinking: nil,
      effort: nil
    ]

    @type t :: %__MODULE__{
            name: atom() | String.t(),
            description: String.t() | nil,
            model: String.t(),
            provider: {module(), keyword()},
            system_prompt: String.t() | nil,
            tools: [module()],
            temperature: float() | nil,
            max_tokens: pos_integer() | nil,
            max_iterations: pos_integer(),
            thinking: term(),
            effort: atom() | nil
          }
  end

  @tool_timeout 30_000

  # --- Client API ---

  @doc "Start an agent process from a `Config`."
  def start_link(%Config{} = config, opts \\ []) do
    GenServer.start_link(__MODULE__, config, opts)
  end

  @doc "Run the agentic loop for `input`. Blocks the caller (not the scheduler)."
  def run(agent, input, ctx \\ %{}) when is_binary(input) do
    GenServer.call(agent, {:run, input, ctx}, :infinity)
  end

  @doc "Return the accumulated conversation history (excludes the system prompt)."
  def history(agent), do: GenServer.call(agent, :history)

  @doc "Clear the conversation history."
  def reset(agent), do: GenServer.call(agent, :reset)

  # --- Server ---

  @impl GenServer
  def init(%Config{} = config) do
    {:ok, %{config: config, history: []}}
  end

  @impl GenServer
  def handle_call({:run, input, ctx}, _from, %{config: config, history: history} = state) do
    messages = system_messages(config) ++ history ++ [%{role: :user, content: input}]

    case loop(messages, config, ctx, 0) do
      {:ok, response, final_messages} ->
        new_history = Enum.reject(final_messages, &(&1.role == :system))
        {:reply, {:ok, response}, %{state | history: new_history}}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call(:history, _from, state), do: {:reply, state.history, state}
  def handle_call(:reset, _from, state), do: {:reply, :ok, %{state | history: []}}

  # --- The agentic loop ---

  defp loop(messages, %Config{max_iterations: max}, _ctx, iteration)
       when iteration >= max do
    {:error, {:max_iterations, messages}}
  end

  defp loop(messages, %Config{provider: {provider_mod, popts}} = config, ctx, iteration) do
    case provider_mod.complete(messages, build_opts(config, popts)) do
      {:ok, %Response{tool_calls: tool_calls} = response}
      when tool_calls == [] or tool_calls == nil ->
        {:ok, response, messages ++ [assistant_message(response)]}

      {:ok, %Response{tool_calls: tool_calls} = response} ->
        tool_messages = run_tools(tool_calls, config, ctx)
        next = messages ++ [assistant_message(response)] ++ tool_messages
        loop(next, config, ctx, iteration + 1)

      {:error, _reason} = error ->
        error
    end
  end

  # Run every requested tool concurrently under a supervised Task, isolating
  # crashes and enforcing a timeout. Results are returned in request order.
  defp run_tools(tool_calls, config, ctx) do
    AgentSea.ToolTaskSup
    |> Task.Supervisor.async_stream_nolink(
      tool_calls,
      fn call -> run_one_tool(call, config, ctx) end,
      timeout: @tool_timeout,
      on_timeout: :kill_task,
      max_concurrency: max(length(tool_calls), 1)
    )
    |> Enum.zip(tool_calls)
    |> Enum.map(fn
      {{:ok, result}, call} -> tool_result_message(call, result)
      {{:exit, reason}, call} -> tool_result_message(call, {:error, {:tool_crashed, reason}})
    end)
  end

  defp run_one_tool(%ToolCall{name: name, arguments: args}, %Config{tools: tools}, ctx) do
    case find_tool(tools, name) do
      nil -> {:error, {:unknown_tool, name}}
      tool_mod -> tool_mod.run(args, ctx)
    end
  end

  defp find_tool(tools, name), do: Enum.find(tools, fn mod -> mod.name() == name end)

  # --- Message helpers ---

  defp system_messages(%Config{system_prompt: nil}), do: []
  defp system_messages(%Config{system_prompt: prompt}), do: [%{role: :system, content: prompt}]

  defp assistant_message(%Response{content: content, tool_calls: tool_calls}) do
    %{role: :assistant, content: content, tool_calls: tool_calls || []}
  end

  defp tool_result_message(%ToolCall{} = call, {:ok, value}) do
    %{role: :tool, tool_call_id: call.id, name: call.name, content: stringify(value)}
  end

  defp tool_result_message(%ToolCall{} = call, {:error, reason}) do
    %{role: :tool, tool_call_id: call.id, name: call.name, content: "Error: #{inspect(reason)}"}
  end

  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: inspect(value)

  # --- Provider options ---

  defp build_opts(%Config{} = config, popts) do
    computed =
      [model: config.model]
      |> put_opt(:system_prompt, config.system_prompt)
      |> put_opt(:temperature, config.temperature)
      |> put_opt(:max_tokens, config.max_tokens)
      |> put_opt(:thinking, config.thinking)
      |> put_opt(:effort, config.effort)
      |> put_opt(:tools, tool_specs(config.tools))

    Keyword.merge(popts, computed)
  end

  defp tool_specs([]), do: nil

  defp tool_specs(tools) do
    Enum.map(tools, fn mod ->
      %{name: mod.name(), description: mod.description(), schema: mod.schema()}
    end)
  end

  defp put_opt(opts, _key, nil), do: opts
  defp put_opt(opts, _key, []), do: opts
  defp put_opt(opts, key, value), do: Keyword.put(opts, key, value)
end
