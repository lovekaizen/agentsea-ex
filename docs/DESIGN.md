# AgentSea on the BEAM — Idiomatic Elixir Rewrite (Design Doc)

**Status:** Draft / RFC
**Scope:** A *full native rewrite* in Elixir — **not** a 1:1 port of the TypeScript ADK. Where the TS design exists only to work around things Node lacks (manual concurrency, `Promise.race` plumbing, hand-rolled retry/abort state machines, mock-execution stubs, a WebSocket SPA), this design deletes the workaround and uses the platform.
**Working name:** `agentsea` (Hex), an umbrella of `agentsea_*` apps.

> **Note:** this is a planning artifact for a *separate* Elixir project. It intentionally does not live in the TypeScript repo.

---

## 1. Why a rewrite, not a port

The TypeScript ADK hand-rolls a large amount of machinery that the BEAM provides as primitives. A literal port would translate the *workarounds* for problems OTP doesn't have:

| AgentSea (TS) hand-rolls… | OTP gives for free |
| --- | --- |
| Crew agents as objects + manual busy/idle tracking | One process per agent, supervised |
| `DelegationCoordinator` + `Semaphore` + `AgentPool` | Message passing + `Task.async_stream` + a `Registry` |
| Auction `bidOnTask` collected via Promises | `GenServer` multi-call fan-out with a per-bid timeout |
| `kickoff/pause/resume/abort` flags on a class | A supervised `gen_statem` |
| Retry/failover `try/catch` ladders | "Let it crash" + supervisor restart strategies |
| Gateway `CircuitBreaker` class + `HealthMonitor` | `:fuse` + `Finch` pools + a router process |
| `DAGExecutor` with manual concurrency + cycle detection | `:digraph` + `Task.async_stream` / `Flow` over a process graph |
| `admin-ui` SPA + `analytics` + `debugger` over WebSockets | Phoenix LiveView + Telemetry + PubSub |
| `EvaluationPipeline` parallelism config (was buggy) | `Broadway` — concurrency is a setting |
| `LocalProvider` ONNX stub / `embeddings` package | `Bumblebee` + `Nx` (in-process, first-class) |
| `structured` (Zod → validated object) | `Instructor` (LLM → validated Ecto changeset) |
| pgvector "phantom" store | `pgvector` + `Ecto` (first-class) |

The headline insight: AgentSea's most hand-rolled complexity is exactly the **orchestration + observability** slice — and that's precisely where the BEAM most outclasses Node. We win by *deleting* that stack.

---

## 2. Design principles

1. **Processes are the unit of concurrency, isolation, and failure.** An agent is a process. A crew is a supervision tree. A task is a `Task`. We never hand-roll a scheduler, a semaphore, or an abort flag — OTP already has them.
2. **Let it crash.** Errors that aren't part of the domain (a provider 500, a tool raising) are not caught-and-stringified into a result object; they crash the worker, and a supervisor decides restart policy. Domain *outcomes* use tagged tuples (`{:ok, _}` / `{:error, _}`).
3. **Behaviours over inheritance, structs over classes, supervision trees over lifecycle methods, Telemetry over bespoke event emitters.**
4. **Data is data.** Config is plain keyword lists / structs validated by `NimbleOptions`. No config "classes."
5. **API parity is a non-goal.** Keep the AgentSea *concepts* (Agent, Provider, Tool, Memory, Crew, Role, Capability, delegation strategy, Gateway, evaluation) — they're good domain modeling. Discard the *shapes* (no `EventEmitter`, no async-generator-as-stream, no class constructors with injected deps).
6. **Observability is first-class, not bolted on.** Every meaningful step emits a `:telemetry` event; the debugger/dashboard are LiveView consumers of those events.

Rule of thumb across the whole design: **where OTP already solves it, delete the abstraction and use the primitive.**

---

## 3. Naming & project layout

An **umbrella** mirrors the existing package split while letting BEAM apps depend on each other and ship independently. Apps depend only "downward" (`crews` → `core`; `web` → everything). A user adds only the apps they need to their `mix.exs`.

```
agentsea/                       # umbrella
  apps/
    agentsea_core/         # Agent, Provider/Tool/Memory behaviours, structs, exec loop
    agentsea_providers/    # Anthropic, OpenAI, Gemini, Ollama, OpenAI-compatible
    agentsea_tools/        # built-in tools + tool registry helpers
    agentsea_memory/       # buffer/summary/vector adapters (ETS/Mnesia/Ecto/pgvector/Redis)
    agentsea_crews/        # crews, roles, delegation strategies, DAG
    agentsea_gateway/      # routing, :fuse, Finch pools, OpenAI-compatible server
    agentsea_embeddings/   # Bumblebee/Nx + pgvector
    agentsea_structured/   # Instructor-based structured output
    agentsea_ingest/       # Broadway ingestion pipelines
    agentsea_evaluate/     # Broadway evaluation + LLM-as-judge
    agentsea_mcp/          # MCP client (Hermes or native), tool adapter
    agentsea_guardrails/   # content safety, PII, prompt-injection
    agentsea_surf/         # Port bridge to a Node/Playwright sidecar
    agentsea_web/          # Phoenix LiveView: debugger, analytics, admin + OpenAI-compat API
  config/
  mix.exs
```

Hex packages publish per app (`agentsea_core`, `agentsea_crews`, …) under one Hex org, matching the existing `@lov3kaizen/agentsea-*` npm split so docs map mentally even though the code is idiomatic.

**Naming fork:** `AgentSea.*` modules (discoverable, mirrors the brand) vs. short `Sea.*` (matches the `sea` CLI, terser). This doc uses `AgentSea.*`.

---

## 4. Core domain — behaviours & structs

### 4.1 The three behaviours

Everything pluggable in the TS version (`LLMProvider`, `Tool`, `MemoryStore`) becomes a **behaviour**. These three are the entire extension surface of the core.

```elixir
defmodule AgentSea.Provider do
  @moduledoc "A chat-completion backend (Anthropic, OpenAI, local, …)."

  @type message :: %{role: :system | :user | :assistant | :tool, content: term()}
  @type opts :: keyword()

  @doc "Single completion. Returns a normalized response struct."
  @callback complete([message], opts) :: {:ok, AgentSea.Response.t()} | {:error, term()}

  @doc """
  Streaming completion. Returns a lazy Stream of normalized chunks.
  Implementations build this from Req/Finch SSE — no async-generator plumbing.
  """
  @callback stream([message], opts) :: Enumerable.t()

  @doc "Static model capabilities — used by the gateway and for validation."
  @callback model_info(model :: String.t()) :: AgentSea.ModelInfo.t() | nil

  @optional_callbacks stream: 2
end
```

```elixir
defmodule AgentSea.Tool do
  @moduledoc "A callable tool. The schema is a NimbleOptions/peri spec, not Zod."

  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback schema() :: keyword()           # NimbleOptions schema for params
  @callback run(params :: map(), ctx :: AgentSea.ToolContext.t()) ::
              {:ok, term()} | {:error, term()}

  @doc "Whether a human must approve before execution (HITL)."
  @callback needs_approval?() :: boolean()
  @optional_callbacks needs_approval?: 0
end
```

```elixir
defmodule AgentSea.Memory do
  @callback save(conv_id :: String.t(), [AgentSea.Provider.message()]) :: :ok
  @callback load(conv_id :: String.t()) :: [AgentSea.Provider.message()]
  @callback clear(conv_id :: String.t()) :: :ok
  @callback search(query :: String.t(), limit :: pos_integer()) ::
              [AgentSea.Provider.message()]
  @optional_callbacks search: 2
end
```

> **Idiom note:** the TS `Tool` carries an inline `execute` closure and a Zod schema; in Elixir a tool is a *module* implementing the behaviour — introspectable, testable, supervisable. Define-by-closure is still supported via a tiny `AgentSea.Tool.Fun` wrapper for ad-hoc tools, but the canonical tool is a module.

### 4.2 Normalized data as structs

```elixir
defmodule AgentSea.Response do
  @enforce_keys [:content, :stop_reason, :usage]
  defstruct [:content, :stop_reason, :usage, :tool_calls, :raw]
  @type t :: %__MODULE__{
          content: String.t(),
          stop_reason: :stop | :tool_use | :length | :error,
          usage: %{input_tokens: non_neg_integer(), output_tokens: non_neg_integer()},
          tool_calls: [AgentSea.ToolCall.t()],
          raw: term()
        }
end
```

Stream chunks are plain tagged tuples flowing through a `Stream`: `{:content, binary}`, `{:tool_call, partial}`, `{:thinking, binary}`, `:done`. Consumers pattern-match; there is no chunk-type enum class.

### 4.3 The Agent — a `GenServer` with a real lifecycle

In TS the agent is a method-bag whose "state" (tasks completed, tokens used, busy flag) lives in instance fields and whose loop is an `async` function. In Elixir the agent **is** its state — supervised, addressable, introspectable. Deps are resolved from config (module + opts) at `init`; there is no `new Agent(config, provider, registry, memory)` constructor with injected deps.

```elixir
defmodule AgentSea.Agent do
  use GenServer

  defmodule Config do
    @enforce_keys [:name, :model, :provider]
    defstruct name: nil, description: nil, model: nil,
              provider: nil,                 # {module, opts}
              system_prompt: nil,
              tools: [],                     # [module]
              memory: {AgentSea.Memory.Buffer, []},
              temperature: nil, max_tokens: nil,
              max_iterations: 10,
              # Claude-specific, passed through to the provider:
              thinking: nil,                 # nil | :adaptive | {:adaptive, display: :summarized}
              effort: nil                    # :low | :medium | :high | :xhigh | :max
  end

  # --- public API ---
  def start_link(%Config{} = cfg, opts \\ []),
    do: GenServer.start_link(__MODULE__, cfg, opts)

  @doc "Blocking run; returns the final AgentSea.Response. Blocks the caller, not the scheduler."
  def run(agent, input, ctx \\ %{}), do: GenServer.call(agent, {:run, input, ctx}, :infinity)

  @doc "Streaming run. Returns a Stream of events the caller drives lazily."
  def stream(agent, input, ctx \\ %{}), do: AgentSea.Agent.Stream.new(agent, input, ctx)

  @doc "Bid on a task (used by the auction strategy)."
  def bid(agent, task), do: GenServer.call(agent, {:bid, task})

  # --- server ---
  @impl true
  def handle_call({:run, input, ctx}, _from, %Config{} = cfg) do
    case loop(build_messages(cfg, input), cfg, ctx, 0) do
      {:done, resp, _msgs} -> {:reply, {:ok, resp}, cfg}
      {:max_iterations, _} -> {:reply, {:error, :max_iterations}, cfg}
    end
  end
end
```

`pause`/`resume`/`abort` become process/`Task` lifecycle (kill the task, transition state) — nothing has to thread a cancellation token through every `await`. **The TS "return random mock tokens if no executor" branch does not exist here** — a provider is a required dependency, expressed cleanly, not a fallback stub.

#### The agentic loop (idiomatic)

The TS loop (load history → call provider → parse tool calls → run tools in parallel → append → repeat ≤ `max_iterations`) maps cleanly. Tool fan-out is `Task.async_stream` against the agent's `Task.Supervisor`, so a crashing tool is isolated and timeouts are first-class.

```elixir
defp loop(messages, %Config{} = cfg, ctx, iteration) when iteration < cfg.max_iterations do
  {provider_mod, popts} = cfg.provider
  {:ok, resp} = provider_mod.complete(messages, build_opts(cfg, popts))

  case resp.tool_calls do
    [] ->
      {:done, resp, messages}

    calls ->
      results =
        Task.Supervisor.async_stream_nolink(
          AgentSea.ToolTaskSup, calls,
          fn call -> {call, run_tool(call, cfg.tools, ctx)} end,
          timeout: tool_timeout(cfg), on_timeout: :kill_task, max_concurrency: length(calls)
        )
        |> Enum.map(&normalize_tool_result/1)

      loop(messages ++ assistant_and_tool_msgs(resp, results), cfg, ctx, iteration + 1)
  end
end

defp loop(messages, _cfg, _ctx, _iteration), do: {:max_iterations, messages}
```

A tool that raises doesn't take down the agent: `async_stream_nolink` converts the crash into `{:exit, reason}`, which we fold into a `{:error, _}` tool result and feed back to the model (matching the TS retry semantics without the `try/catch`).

### 4.4 Tool registry — just a `Registry` + config

The TS `ToolRegistry` (register/get/has/execute-with-retry) collapses. Tools are modules; "registration" is config (`tools: [WeatherTool, SearchTool]`). For dynamic/runtime tools (MCP-sourced), use a `Registry`:

```elixir
{:ok, _} = Registry.start_link(keys: :unique, name: AgentSea.ToolRegistry)
# an MCP client registers each discovered tool module/closure under its name
```

Param validation is `NimbleOptions.validate(params, tool.schema())` at call time. The *default* posture is "let the tool crash and report," not a retry ladder.

---

## 5. Providers — Req streaming, `Instructor` for structured

Each provider is a module implementing `AgentSea.Provider`. HTTP is **`Req`** (on `Finch`); SSE streaming is a `Stream.resource/3` over the chunked body. No official-SDK dependencies — LLM APIs are HTTP+SSE and `Req` makes that trivial. Every call is wrapped in `:telemetry.span/3` so integrators get metrics for free.

```elixir
defmodule AgentSea.Providers.Anthropic do
  @behaviour AgentSea.Provider

  @impl true
  def complete(messages, opts) do
    :telemetry.span([:agentsea, :provider, :complete], %{model: opts[:model]}, fn ->
      result =
        Req.post(req(opts), json: body(messages, opts, stream: false))
        |> normalize()

      {result, %{}}
    end)
  end

  @impl true
  def stream(messages, opts) do
    Stream.resource(
      fn -> start_sse(messages, opts) end,
      &next_sse_event/1,
      &close_sse/1
    )
  end

  @impl true
  def model_info("claude-opus-4-8"), do: %AgentSea.ModelInfo{
        context_window: 1_000_000, tools: true, vision: true, thinking: true,
        effort: [:low, :medium, :high, :xhigh, :max]}
  # …
end
```

### 5.1 Per-model "type safety" — the honest trade-off

This is the one place the TS version is genuinely ahead (compile-time rejection of unsupported params per model). Elixir is dynamic; we don't replicate that DX exactly. The pragmatic answer is **runtime validation against `model_info/1`** plus `@spec`/Dialyzer and set-theoretic types (Elixir 1.18+):

```elixir
defp build_opts(%Config{model: model} = cfg, popts) do
  info = provider_for(cfg).model_info(model) || raise ArgumentError, "unknown model #{model}"
  []
  |> put_if(info.thinking, :thinking, cfg.thinking)
  |> put_if(info.effort != [], :effort, validate_member(cfg.effort, info.effort))
  |> NimbleOptions.validate!(provider_opts_schema(info))
end
```

Capability mismatches surface as clear runtime errors at agent start (fail fast on `init`), not at the first request. Documented as a deliberate, known divergence.

### 5.2 Structured output

`agentsea_structured` wraps **`Instructor`**: instead of `Zod schema → validated object`, it's `Ecto schema → validated changeset`. Same capability, idiomatic shape, and *more* expressive for nested/cross-field rules.

```elixir
defmodule Receipt do
  use Ecto.Schema
  use Instructor.Validator
  embedded_schema do
    field :merchant, :string
    field :total_cents, :integer
  end
  @impl true
  def validate_changeset(cs), do: Ecto.Changeset.validate_number(cs, :total_cents, greater_than: 0)
end

AgentSea.Structured.extract(agent, input, into: Receipt)
```

---

## 6. Memory — Ecto, pgvector, Bumblebee

The `Memory` behaviour (§4.1) has adapters:

- `AgentSea.Memory.Buffer` — a `GenServer` (or ETS table) holding the rolling window. Replaces `BufferMemory`.
- `AgentSea.Memory.Summary` — compresses old turns via a provider call. Replaces `SummaryMemory`.
- `AgentSea.Memory.Vector` — **`pgvector` via `Ecto`**; the TS "phantom pgvector store" is a first-class, real adapter here. Embeddings come from `Bumblebee` (in-process HF/ONNX) *or* a remote embeddings provider.
- Multi-tenancy (`TenantBufferMemory`) is **per-tenant process isolation**: a `DynamicSupervisor` of memory processes keyed by tenant in a `Registry`, instead of a tenant-prefixed map. True isolation, not namespacing.

Episodic / semantic / working memory become three behaviour-implementing modules sharing the vector adapter, distinguished by retention policy and scope rather than three subclasses.

---

## 7. Crews — the headline feature

This is where the BEAM story sells itself: **agents are supervised processes, delegation is message passing, failover is a restart strategy, the auction is a `GenServer` fan-out.** It's also where the TS ADK carries its most hand-rolled complexity (a task queue, ready-task gating, retries, a Promise-collected auction, a delegation coordinator).

### 7.1 Supervision tree

```
AgentSea.Crew.Supervisor                (one per kicked-off crew)
├── AgentSea.Crew.Coordinator           (gen_statem: idle→running→paused→…)
├── AgentSea.Crew.AgentSup              (DynamicSupervisor — one child per agent)
│   ├── AgentSea.Agent  (role: researcher)
│   ├── AgentSea.Agent  (role: writer)
│   └── AgentSea.Agent  (role: critic)
├── AgentSea.Crew.SharedMemory          (GenServer/ETS, PubSub-backed)
├── AgentSea.Crew.TaskSup               (Task.Supervisor for delegated work)
└── Registry (keys: :unique) → agent name → pid
```

Each crew kickoff starts its own subtree under a top-level `DynamicSupervisor`. Aborting a crew = terminating its subtree. There is no manual `isBusy` bookkeeping — an agent is "busy" iff it's mid-`call`; availability is derived, and the `Registry` is the source of truth for membership.

### 7.2 Coordinator as `gen_statem`

The TS `Crew` lifecycle (`kickoff/pause/resume/abort/reset`, status `idle|running|paused|completed|failed|aborted`) is exactly a state machine. `gen_statem` gives us the states, legal transitions (e.g. `restore_checkpoint` only from `idle`), and timeouts for free.

```elixir
defmodule AgentSea.Crew.Coordinator do
  @behaviour :gen_statem
  # states: :idle | :running | :paused | :completed | :failed | :aborted

  def kickoff(crew),    do: :gen_statem.call(crew, :kickoff)
  def pause(crew),      do: :gen_statem.call(crew, :pause)
  def resume(crew),     do: :gen_statem.call(crew, :resume)
  def abort(crew),      do: :gen_statem.cast(crew, :abort)
  def checkpoint(crew), do: :gen_statem.call(crew, :checkpoint)
end
```

The coordinator owns the task DAG and drives execution. Ready tasks are dispatched to agents as supervised `Task`s; completion arrives as a message — no polling, no shared mutable queue:

```elixir
# A task finished — record it, unlock dependents, dispatch the next wave.
def running(:info, {ref, {:task_done, task_id, result}}, data) do
  Process.demonitor(ref, [:flush])
  data = data |> record_result(task_id, result) |> unlock_dependents(task_id)

  if all_done?(data) do
    AgentSea.PubSub.broadcast(data.crew, {:crew_completed, summarize(data)})
    {:next_state, :completed, data}
  else
    {:keep_state, dispatch_ready_tasks(data)}
  end
end

# A task process crashed — supervisor-style policy, no try/catch.
def running(:info, {:DOWN, _ref, :process, _pid, reason}, data),
  do: {:keep_state, retry_or_fail(data, reason)}

defp dispatch_ready_tasks(data) do
  Enum.reduce(ready_tasks(data), data, fn task, d ->            # deps satisfied
    {:ok, agent} = AgentSea.Crew.Delegation.select(d.strategy, task, d.agents)
    Task.Supervisor.async_nolink(d.task_sup, fn ->
      {:ok, resp} = AgentSea.Agent.run(agent, AgentSea.Crew.Task.input(task))
      {:task_done, task.id, resp}
    end)
    mark_dispatched(d, task)
  end)
end
```

**Checkpoint/restore** serializes coordinator state (context, task queue, results, timeline, iteration) to a term/JSON — same as `createCheckpoint()/restoreCheckpoint()` — but because state lives in one process, snapshotting is a single read, not a walk over many objects.

### 7.3 Delegation strategies — a behaviour

The five TS strategies (`round-robin`, `best-match`, `auction`, `hierarchical`, `consensus`) become a behaviour with a module per strategy, selected by config, with the same fallback chain (`enable_fallback`, `fallback_order`, `max_attempts`).

```elixir
defmodule AgentSea.Crew.Delegation do
  @type task :: AgentSea.Crew.Task.t()
  @type agent :: %{name: String.t(), pid: pid(), role: AgentSea.Role.t()}

  @callback delegate(task, [agent], ctx :: map()) ::
              {:ok, AgentSea.Crew.DelegationResult.t()} | {:error, term()}
end
```

`DelegationResult` keeps its shape: `selected_agent`, `reason`, `confidence`, `alternatives`, `decision_time_ms`.

### 7.4 The auction — `GenServer` fan-out, not Promise plumbing

This is the demo. The TS auction collects `agent.bidOnTask(task)` Promises, filters by capability + `minimumBid`, picks by `confidence|fastest|cheapest`. In Elixir it's a **parallel multi-call with a per-bid timeout** — the bidding window *is* the call timeout.

```elixir
defmodule AgentSea.Crew.Delegation.Auction do
  @behaviour AgentSea.Crew.Delegation

  @impl true
  def delegate(task, agents, ctx) do
    eligible = Enum.filter(agents, &capable?(&1, task))

    bids =
      Task.async_stream(
        eligible,
        fn a -> {a, AgentSea.Agent.bid(a.pid, task)} end,   # GenServer.call w/ bid timeout
        timeout: ctx.bidding_time_ms,                       # default 5_000
        on_timeout: :kill_task
      )
      |> Stream.filter(&match?({:ok, {_a, {:ok, _bid}}}, &1))
      |> Enum.map(fn {:ok, {a, {:ok, bid}}} -> {a, bid} end)
      |> Enum.filter(fn {_a, bid} -> bid.confidence >= ctx.minimum_bid end)

    case select(bids, ctx.selection_criteria) do
      nil -> {:error, :no_bids}
      {agent, bid} -> {:ok, result(agent, bid, bids)}
    end
  end

  defp select(bids, :confidence), do: Enum.max_by(bids, fn {_, b} -> b.confidence end, fn -> nil end)
  defp select(bids, :fastest),    do: Enum.min_by(bids, fn {_, b} -> b.estimated_time end, fn -> nil end)
  defp select(bids, :cheapest),   do: Enum.min_by(bids, fn {_, b} -> b.estimated_cost end, fn -> nil end)
end
```

`AgentSea.Agent.bid/2` is a `handle_call` the agent answers from its role/capabilities — `estimated_cost` = model price tier × `estimated_time` (exactly the TS `TaskBid`). Slow or dead bidders simply miss the window (`on_timeout: :kill_task`); no `Promise.race`, no leaked timers.

> **Consensus** (which the TS version faked with `Math.random()` votes) is honest here because asking N agents to vote *is* N `GenServer.call`s — real deliberation collected with `Task.async_stream`, agreement computed over actual returned values. There's no temptation to stub it because the real thing is no harder to write.

### 7.5 Roles & capabilities

`Role` and `Capability` stay as structs (they're good data). `RoleConfig` → `%AgentSea.Role{}` with `capabilities`, `system_prompt`, `goals`, `constraints`, `backstory`, `can_delegate`, `can_receive_delegation`, `max_concurrent_tasks`. Capability matching (`matched/missing/score/can_execute`, proficiency `novice|intermediate|expert|master`, keyword relevance) is **pure functions** in `AgentSea.Capability` — trivially unit-testable, no object state.

### 7.6 Workflows / DAG — `:digraph` + `Flow`

The TS `DAGExecutor` (cycle detection, `maxParallel` semaphore, per-node timeout/retry, node states, streamed events) maps to either:

- **Pure orchestration:** build the dependency graph with `:digraph`, topologically layer it, and run each layer with `Task.async_stream` (`max_concurrency` = `max_parallel`). Cycle detection is `:digraph_utils.is_acyclic/1` — we delete the hand-written `detectCycle()`. Independent steps run in parallel *by construction* (the "sequential chain" bug is structurally impossible).
- **Throughput-heavy / streaming:** `Flow`/`GenStage` when nodes are data-parallel stages with backpressure.

Validation (`cycles`, `missing deps`, `missing handlers`) is a pure `validate/1` returning `{:ok, dag} | {:error, reasons}`. Node states (`pending|running|completed|failed|skipped`) and events emit via **Telemetry** (`[:agentsea, :dag, :node, :start]` …) so the LiveView dashboard subscribes without bespoke wiring. `ParallelExecutor` / `Semaphore` / `AgentPool` all disappear.

### 7.7 Shared memory — ETS + PubSub

`SharedMemory` (namespaced KV, `set_shared/get_shared/broadcast`, per-agent namespaces, change history) becomes an **ETS table** owned by a `GenServer`, with changes published over **`Phoenix.PubSub`**. `broadcast/3` is literally a PubSub broadcast. Cross-node sharing comes free if the table is replicated or fronted by a distributed process.

---

## 8. Gateway — Finch pools, `:fuse`, a router process

Bread-and-butter BEAM. The TS `Gateway` maps directly:

| TS concept | Elixir |
| --- | --- |
| `RoutingStrategyInterface` (RoundRobin/Failover/CostOptimized/LatencyOptimized) | `AgentSea.Gateway.Router` behaviour + a module per strategy |
| `CircuitBreaker` (closed/open/half-open) | **`:fuse`** (battle-tested), one fuse per provider |
| `HealthMonitor` (healthy/degraded/unhealthy, latency, error rate) | a `GenServer` doing periodic `health_check`, state in ETS, Telemetry events |
| provider connection reuse | **`Finch`** pools (`nimble_pool`) per provider host |
| retry (≤3, exclude failed, `error.retryable`) | router recursion over the candidate list; `Req` retry for transport |
| `RateLimitConfig` (rpm/rph/tpm/concurrent) | a token-bucket `GenServer` per tenant/provider, or `Hammer` |
| exact cache | `Nebulex`/ETS keyed by `hash_request/1` |
| semantic cache | pgvector lookup over request embeddings (real, not stubbed) |
| OpenAI-compatible HTTP + SSE | **`Phoenix`/`Bandit`** endpoint, SSE via `Plug.Conn.chunk/2` |
| Prometheus + events | `Telemetry` + `TelemetryMetricsPrometheus` |

Virtual models (`best`/`cheapest`/`fastest`) are router functions over `model_info` + live health. `RoutingContext` (`exclude_providers`, `preferred_provider`, `max_cost`, `max_latency`, `previous_attempts`) is a struct threaded through the router.

```elixir
defmodule AgentSea.Gateway.Router do
  @callback choose([candidate], RoutingContext.t()) :: {:ok, candidate} | {:error, :no_provider}
end

# call site:
def completion(req, ctx) do
  with {:ok, cand} <- strategy().choose(candidates(req), ctx),
       :ok <- :fuse.ask(fuse(cand), :sync),
       {:ok, resp} <- run(cand, req) do
    {:ok, resp}
  else
    {:error, :blown} -> completion(req, exclude(ctx, cand))   # circuit open → next candidate
    {:error, _} = e  -> maybe_failover(e, req, ctx)
  end
end
```

---

## 9. Observability — the second big win, basically free

The TS `admin-ui` (React SPA) + `analytics` + `debugger` (step-through, checkpoint replay, what-if) collapse into **Phoenix LiveView + Telemetry + PubSub**:

- **Live fleet view:** every crew subtree's agents render live; subscribe to `[:agentsea, :agent, :*]` and `[:agentsea, :crew, :*]` Telemetry. Token streaming shows up as it happens.
- **Step-through debugger:** the coordinator already pauses/resumes; LiveView drives it and renders the message history per step. Checkpoint replay = restore a serialized coordinator state and re-run.
- **What-if:** clone a checkpoint into a fresh crew subtree with altered config — isolation is free because it's a separate supervision subtree.
- **Fleet introspection:** `:observer` / `LiveDashboard` out of the box.

Costs, latency p50/p95/p99, token counters, and cache hit rate are `Telemetry.Metrics` definitions feeding both the LiveView and a Prometheus exporter. We delete the SPA, the WebSocket plumbing, and the bespoke `EventEmitter` bus. **This is the screenshot that sells the project.**

---

## 10. Ingest & Evaluate — `Broadway`

- `agentsea_ingest`: parsers → chunkers → transformers → embedder → vector store is a **`Broadway`** topology. Backpressure, batching, concurrency, retries, and acknowledgement are settings. The TS `EvaluationPipeline` parallelism bug is structurally impossible — concurrency is `processors: [default: [concurrency: N]]`.
- `agentsea_evaluate`: metrics, LLM-as-judge, human feedback, and continuous monitoring as a Broadway pipeline over an evaluation dataset; judge calls go through the gateway; results stream to the LiveView dashboard via Telemetry.

---

## 11. Embeddings & local models — an upgrade, not a port

Where Elixir *beats* the TS SDK. Local embeddings/models run **in-process** via `Bumblebee` + `Nx` (EXLA backend). The `LocalProvider` ONNX gap that had to be stubbed out in TS is a real, first-class feature here — load a HF model and serve it with `Nx.Serving` (batched, GPU-aware, distributable):

```elixir
{:ok, model} = Bumblebee.load_model({:hf, "sentence-transformers/all-MiniLM-L6-v2"})
{:ok, tok}   = Bumblebee.load_tokenizer({:hf, "sentence-transformers/all-MiniLM-L6-v2"})

serving =
  Bumblebee.Text.text_embedding(model, tok,
    compile: [batch_size: 32], defn_options: [compiler: EXLA])

# Add `serving` to the supervision tree; call Nx.Serving.batched_run/2 from anywhere.
```

The vector store is `pgvector` via Ecto (first-class), with an `AgentSea.VectorStore` behaviour for Pinecone/Qdrant/Chroma adapters over `Req`.

---

## 12. The harder fits — be honest, bridge don't fake

- **`surf` (browser / computer-use):** weakest fit. No Playwright-equivalent maturity on BEAM; `Wallaby` exists but computer-use/vision needs native input. **Decision: bridge to a Node/Playwright sidecar via a `Port`** (`agentsea_surf` owns the supervised port, restarts the sidecar on crash). The vision loop (screenshot → Claude vision → action) stays in Elixir; only OS/browser I/O is delegated. Expose the same `AgentSea.Tool` behaviour so agents call browser tools identically.
- **MCP:** use **`Hermes`** (MCP for Elixir) where it's mature; otherwise a thin native client (`stdio` via `Port`, SSE/streamable-HTTP via `Req`). `MCPRegistry`/`MCPClient` → a `DynamicSupervisor` of client processes in a `Registry`; `mcpToolToAgenticTool` → an adapter registering each discovered tool into `AgentSea.ToolRegistry`.
- **Provider SDKs:** none needed; `Req`/`Finch` over HTTP+SSE. Non-problem.
- **Voice (TTS/STT):** Whisper/local via `Bumblebee`; remote (ElevenLabs/OpenAI) via `Req`. Same provider-style behaviour.

---

## 13. Application-level supervision tree

```
AgentSea.Application
├── Finch (named pools per provider host)
├── Phoenix.PubSub
├── AgentSea.ToolRegistry            (Registry)
├── AgentSea.Telemetry               (handlers + metrics reporters)
├── AgentSea.Gateway.Supervisor
│   ├── Router config
│   ├── HealthMonitor (GenServer + ETS)
│   ├── :fuse instances per provider
│   ├── RateLimiter(s)
│   └── Cache (Nebulex/ETS)
├── AgentSea.MCP.Supervisor          (DynamicSupervisor of MCP clients)
├── AgentSea.Crew.RootSupervisor     (DynamicSupervisor of per-crew subtrees)
├── AgentSea.Memory.TenantSupervisor (DynamicSupervisor, per-tenant isolation)
├── AgentSea.Ingest.Pipeline         (Broadway)        # optional / on-demand
├── AgentSea.Evaluate.Pipeline       (Broadway)        # optional / on-demand
├── AgentSea.Surf.PortSupervisor     (Node/Playwright sidecar)
└── AgentSeaWeb.Endpoint             (LiveView dashboard + OpenAI-compat gateway API)
```

Single agents (no crew) start under a lightweight `DynamicSupervisor` too, so `AgentSea.Agent` is always supervised.

---

## 14. Error-handling philosophy

The rule: **domain outcomes are tagged tuples; infrastructure failures are crashes.** This deletes most of the defensive `try/catch` and the "return mock on missing dependency" smell from the TS code.

| Situation | TS SDK today | Native Elixir |
| --- | --- | --- |
| Provider HTTP 500 | caught, stringified into a result | crash the call; `:fuse` melts; router fails over |
| Tool raises | try/catch → error string | task crashes (isolated by `async_stream_nolink`), folded into an `{:error, _}` tool result fed back to the model |
| Bad input / failed guardrail | error object | `{:error, reason}` tagged tuple (a domain outcome) |
| Agent stuck/looping | manual abort flag threaded through awaits | kill the `Task`/process; `AgentSup` restarts it (`:transient`) |
| Partial crew failure | bespoke try/catch bookkeeping | `{:DOWN, …}` message + restart strategy; coordinator re-queues the in-flight task |
| Coordinator crash | — | crew subtree restarts from the last checkpoint (checkpoints are the recovery boundary) |

`errorHandling: 'fail-fast'|'retry'|'fallback'|'continue'` is replaced by supervision strategies + explicit, narrow recovery.

---

## 15. Configuration & DX

- Library config via `keyword` opts to `start_link` (no global singletons); app-level defaults via `config/`.
- A small DSL is *optional*, not required — idiomatic Elixir is "build a `%Config{}` and `start_link`." A `use AgentSea.Crew` macro can generate the child spec for a CrewAI-style declarative feel, but it's sugar over the explicit API, never the only door.
- Telemetry span helpers wrap provider calls, tool runs, and delegation.

### What using it looks like

```elixir
# Single agent
{:ok, agent} =
  AgentSea.Agent.start_link(%AgentSea.Agent.Config{
    name: :researcher,
    provider: {AgentSea.Providers.Anthropic, []},
    model: "claude-opus-4-8",
    tools: [AgentSea.Tools.WebSearch],
    memory: {AgentSea.Memory.Buffer, []}
  })

{:ok, response} = AgentSea.Agent.run(agent, "Summarize today's AI news")

# A crew, declaratively, run under a supervisor
crew =
  AgentSea.Crew.new(
    name: :research_crew,
    strategy: AgentSea.Crew.Delegation.Auction,
    agents: [
      [name: :researcher, role: AgentSea.Roles.researcher(), model: "claude-opus-4-8"],
      [name: :writer,     role: AgentSea.Roles.writer(),     model: "claude-haiku-4-5"]
    ]
  )

{:ok, _sup} = AgentSea.Crew.start_link(crew)
AgentSea.Crew.add_task(:research_crew, description: "Research X", expects: "a brief")
{:ok, result} = AgentSea.Crew.kickoff(:research_crew)
```

Streaming is just a `Stream` the caller consumes:

```elixir
AgentSea.Providers.Anthropic.stream(messages, model: "claude-opus-4-8")
|> Stream.each(fn
  {:content, chunk} -> IO.write(chunk)
  _ -> :ok
end)
|> Stream.run()
```

---

## 16. Testing strategy

- **Behaviours → `Mox`.** Mock `AgentSea.Provider` to test the agent loop deterministically (no network); same for `Tool`/`Memory`. There is no "mock execution" branch baked into production code (the anti-pattern removed from the TS version).
- **Property tests** (`StreamData`) for capability matching, delegation selection, DAG topological ordering, cycle detection.
- **`start_supervised!/1`** for every process under test → no leaked processes between tests; assert on messages and Telemetry events (`:telemetry_test`).
- **Auction/crew concurrency:** deterministic via an injected fake clock/timeout and `Mox` providers returning scripted bids.
- **Golden tests** for provider request/response normalization against recorded fixtures (`Req.Test`).
- **Integration** with a real local provider via `Bumblebee`/Ollama, gated behind a tag so CI without models skips gracefully.

---

## 17. Phasing (the ~80% MVP first)

Recommended scope: **native core where BEAM shines, bridge the rest.** Each phase is independently shippable as Hex packages.

1. **Phase 1 — Core loop (proves the thesis).** `agentsea_core` (Agent GenServer, Provider/Tool/Memory behaviours) + `agentsea_providers` (Anthropic + OpenAI, `Req` streaming) + buffer memory. Deliverable: a streaming, tool-using agent, fully tested via `Mox`.
2. **Phase 2 — Crews (the headline demo).** `DynamicSupervisor` + `gen_statem` coordinator + delegation behaviour + **auction-as-fan-out**. Deliverable: a multi-agent crew you can `kickoff/pause/resume/abort/checkpoint`.
3. **Phase 3 — Observability (the differentiator).** Phoenix LiveView dashboard + Telemetry: live fleet execution, token streaming, checkpoint replay.
4. **Phase 4 — Gateway.** Finch pools + `:fuse` + router + OpenAI-compatible endpoint.
5. **Phase 5 — Data plane.** `Bumblebee` embeddings, pgvector memory, `Instructor` structured output, `Broadway` ingest/evaluate.
6. **Phase 6 — Bridges.** MCP (Hermes/native), `surf` Node sidecar via Port, voice.

**Ship Phase 1→2→3 as the opening statement** — orchestration + observability, the two areas where BEAM most outclasses Node.

---

## 18. TS → Elixir mapping (for porters)

| TS package | Native Elixir | Notes |
| --- | --- | --- |
| `core` (Agent class) | `AgentSea.Agent` GenServer + behaviours | state lives in the process |
| providers | `AgentSea.Provider` behaviour + `Req`/SSE | streaming-first |
| `crews` | Supervisor + `gen_statem` Coordinator + `Registry` | the flagship; delegation = messages |
| workflows / DAG | `:digraph` + `Flow`/`GenStage` | sequential-chain bug structurally impossible |
| `gateway` | `Finch`/`NimblePool` + `:fuse` + Router | failover via fuses |
| `structured` (Zod) | `Instructor` + Ecto changesets | richer validation |
| `embeddings` + local | `Bumblebee`/`Nx` + `pgvector`/Ecto | **upgrade** over TS |
| `memory` | `AgentSea.Memory` behaviour: ETS/Mnesia/Ecto/Redis | per-tenant process isolation |
| `guardrails` | `with`-chained validators | fail-fast tagged tuples |
| `evaluate` / `ingest` | **Broadway** topologies | backpressure built-in |
| `surf` / MCP | `Port` bridge to Node sidecar / Hermes | reuse, don't rebuild |
| `debugger`/`analytics`/`admin-ui` | **Phoenix LiveView** + Telemetry | live, SPA deleted |
| `costs` | Telemetry consumer + Ecto ledger | feeds gateway routing |
| `nestjs` integration | Phoenix integration | `AgentSea.Web` |
| `react` | LiveView (or a thin JS hook lib) | server-driven UI |

---

## 19. Open questions / forks in the road

1. **API parity vs. idiomatic divergence.** Parity eases docs/mental-mapping but forces un-idiomatic patterns (the TS mock-execution and Promise bits don't translate). **Recommendation:** diverge — keep *concept* parity (Agent/Crew/Role/Provider/Tool/delegation/gateway), discard *shape* parity; document the mapping in a "coming from the TS ADK" guide.
2. **Per-model type safety gap.** Accept runtime validation + Dialyzer, or invest in a `defprovider`/macro layer generating per-model typespecs from `model_info`? **Recommendation:** runtime first; revisit macros only if users ask.
3. **Hex org & naming.** One umbrella, per-app packages under an `agentsea` org — confirm the org and whether the umbrella ships as one release or N libraries. (`AgentSea.*` vs short `Sea.*` module namespace.)
4. **Distribution scope for v1.** Single-node first, but design `SharedMemory` and the agent `Registry` so a later swap to `:pg`/`Horde`/a distributed registry is a config change, not a rewrite.
5. **DSL or no DSL.** Ship the explicit struct API for v1; gauge demand for a declarative `use AgentSea.Crew` macro before building it.

---

## 20. The pitch

> *A multi-agent framework where agents are supervised processes, delegation is message passing, the auction is a timed `GenServer` fan-out, failover is a restart strategy, and you watch the whole fleet execute live in LiveView.*

That's a categorically better story than the Node version for the **orchestration + observability** slice — which, not coincidentally, is exactly where the TS ADK carries the most hand-rolled complexity today (the `DelegationCoordinator`/`Semaphore`/`AgentPool`/`EventEmitter`/SPA stack). We win by *deleting* it.
