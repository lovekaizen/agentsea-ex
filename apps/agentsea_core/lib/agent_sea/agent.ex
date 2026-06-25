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
      :role,
      tools: [],
      temperature: nil,
      max_tokens: nil,
      max_iterations: 10,
      # Optional guardrail hooks: a 1-arity fun applied to the user input before
      # the loop / to the final answer before returning. Each returns
      # `{:ok, content}` (possibly rewritten) or `{:block, reason}`. This is
      # exactly `AgentSea.Guardrails.run/2` partially applied.
      input_guard: nil,
      output_guard: nil,
      # Claude-specific, passed through to the provider:
      thinking: nil,
      effort: nil
    ]

    @type guard :: (String.t() -> {:ok, String.t()} | {:block, term()})

    @type t :: %__MODULE__{
            name: atom() | String.t(),
            description: String.t() | nil,
            model: String.t(),
            provider: {module(), keyword()},
            system_prompt: String.t() | nil,
            role: AgentSea.Role.t() | nil,
            tools: [module()],
            temperature: float() | nil,
            max_tokens: pos_integer() | nil,
            max_iterations: pos_integer(),
            input_guard: guard() | nil,
            output_guard: guard() | nil,
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

  @doc """
  Produce a bid for a task, based on the agent's role/capabilities and model
  price tier. Pure (no provider call) — used by the auction delegation strategy.
  The `task` may be any map/struct exposing `:id`, `:description` and
  `:required_capabilities`.
  """
  def bid(agent, task), do: GenServer.call(agent, {:bid, task})

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
    with {:ok, guarded_input} <- guard(config.input_guard, input, :input),
         messages =
           system_messages(config) ++ history ++ [%{role: :user, content: guarded_input}],
         {:ok, response, final_messages} <- run_loop(messages, config, ctx),
         {:ok, content} <- guard(config.output_guard, response.content, :output) do
      new_history = Enum.reject(final_messages, &(&1.role == :system))
      {:reply, {:ok, %{response | content: content}}, %{state | history: new_history}}
    else
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  def handle_call({:bid, task}, _from, %{config: config} = state) do
    {:reply, {:ok, compute_bid(config, task)}, state}
  end

  def handle_call(:history, _from, state), do: {:reply, state.history, state}
  def handle_call(:reset, _from, state), do: {:reply, :ok, %{state | history: []}}

  # --- Guardrail hooks ---

  defp guard(nil, content, _stage), do: {:ok, content}

  defp guard(fun, content, stage) when is_function(fun, 1) do
    case fun.(content) do
      {:ok, guarded} -> {:ok, guarded}
      {:block, reason} -> {:error, {:guardrail, stage, reason}}
    end
  end

  # --- The agentic loop ---

  defp run_loop(messages, config, ctx) do
    meta = %{name: config.name, model: config.model}

    :telemetry.span([:agentsea, :agent, :run], meta, fn ->
      result = loop(messages, config, ctx, 0)
      {result, Map.merge(meta, run_stop_metadata(result))}
    end)
  end

  defp loop(messages, %Config{max_iterations: max}, _ctx, iteration)
       when iteration >= max do
    {:error, {:max_iterations, messages}}
  end

  defp loop(messages, %Config{provider: {provider_mod, popts}} = config, ctx, iteration) do
    meta = %{provider: provider_mod, model: config.model, name: config.name, iteration: iteration}

    completion =
      :telemetry.span([:agentsea, :provider, :complete], meta, fn ->
        r = provider_mod.complete(messages, build_opts(config, popts))
        {r, Map.merge(meta, provider_stop_metadata(r))}
      end)

    case completion do
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

  defp run_one_tool(
         %ToolCall{name: name, arguments: args},
         %Config{tools: tools, name: agent_name},
         ctx
       ) do
    meta = %{tool: name, agent: agent_name}

    :telemetry.span([:agentsea, :tool, :run], meta, fn ->
      result =
        case find_tool(tools, name) do
          nil -> {:error, {:unknown_tool, name}}
          tool -> invoke_tool(tool, args, ctx)
        end

      {result, Map.put(meta, :outcome, elem(result, 0))}
    end)
  end

  defp find_tool(tools, name), do: Enum.find(tools, &(tool_name(&1) == name))

  # Tools may be AgentSea.Tool modules or runtime AgentSea.Tool.Spec values.
  defp tool_name(%AgentSea.Tool.Spec{name: name}), do: name
  defp tool_name(module) when is_atom(module), do: module.name()

  defp invoke_tool(%AgentSea.Tool.Spec{run: run}, args, ctx), do: run.(args, ctx)
  defp invoke_tool(module, args, ctx) when is_atom(module), do: module.run(args, ctx)

  defp tool_description(%AgentSea.Tool.Spec{description: description}), do: description
  defp tool_description(module) when is_atom(module), do: module.description()

  defp tool_schema(%AgentSea.Tool.Spec{schema: schema}), do: schema
  defp tool_schema(module) when is_atom(module), do: module.schema()

  # --- Message helpers ---

  defp system_messages(%Config{} = config) do
    case effective_system_prompt(config) do
      nil -> []
      prompt -> [%{role: :system, content: prompt}]
    end
  end

  # An explicit system_prompt wins; otherwise fall back to the role's prompt.
  defp effective_system_prompt(%Config{system_prompt: sp}) when is_binary(sp), do: sp

  defp effective_system_prompt(%Config{role: %AgentSea.Role{system_prompt: sp}})
       when is_binary(sp),
       do: sp

  defp effective_system_prompt(_), do: nil

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
    Enum.map(tools, fn tool ->
      %{name: tool_name(tool), description: tool_description(tool), schema: tool_schema(tool)}
    end)
  end

  defp put_opt(opts, _key, nil), do: opts
  defp put_opt(opts, _key, []), do: opts
  defp put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  # --- Bidding (auction delegation) ---

  defp compute_bid(%Config{} = config, task) do
    required = Map.get(task, :required_capabilities, [])
    match = AgentSea.Capability.match(role_capabilities(config), required)

    # Reduce confidence when the agent is missing required capabilities.
    confidence = if match.can_execute, do: match.score, else: match.score * 0.5
    estimated_time = estimate_time(task)

    %AgentSea.Bid{
      agent_name: config.name,
      task_id: Map.get(task, :id),
      confidence: confidence,
      estimated_time: estimated_time,
      estimated_cost: AgentSea.ModelPricing.weight(config.model) * estimated_time,
      capabilities: match.matched,
      reasoning:
        "matched #{length(match.matched)} capabilit(ies); #{length(match.missing)} missing"
    }
  end

  defp role_capabilities(%Config{role: %AgentSea.Role{capabilities: caps}}), do: caps
  defp role_capabilities(_), do: []

  # Crude effort estimate (ms) from task description length.
  defp estimate_time(task) do
    description = Map.get(task, :description, "") || ""
    1000 + div(String.length(description), 100) * 500
  end

  # --- Telemetry stop metadata ---

  defp run_stop_metadata({:ok, %Response{} = response, _messages}),
    do: %{outcome: :ok, stop_reason: response.stop_reason}

  defp run_stop_metadata({:error, reason}), do: %{outcome: :error, reason: reason}

  defp provider_stop_metadata({:ok, %Response{} = response}) do
    %{
      outcome: :ok,
      stop_reason: response.stop_reason,
      input_tokens: response.usage.input_tokens,
      output_tokens: response.usage.output_tokens
    }
  end

  defp provider_stop_metadata({:error, reason}), do: %{outcome: :error, reason: reason}
end
