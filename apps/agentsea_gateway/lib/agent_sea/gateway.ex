defmodule AgentSea.Gateway do
  @moduledoc """
  Routes completion requests across multiple providers with strategy-based
  ordering, circuit breaking, and failover.

  A request is *planned* (the strategy orders the available candidates, blown
  fuses and excluded providers removed) and then tried in order in the caller's
  process — so requests stay concurrent. Each attempt records latency and, on
  failure, melts the provider's fuse. When every candidate is exhausted the
  gateway returns `{:error, :all_providers_unavailable}`.

  ## Example

      providers = [
        %AgentSea.Gateway.Provider{name: :primary, module: MyAnthropic, model: "claude-opus-4-8"},
        %AgentSea.Gateway.Provider{name: :backup,  module: MyOpenAI,    model: "gpt-4.1"}
      ]

      {:ok, gw} = AgentSea.Gateway.start_link(%AgentSea.Gateway.Config{
        providers: providers,
        strategy: AgentSea.Gateway.Router.Failover
      })

      {:ok, response, served_by} = AgentSea.Gateway.completion(gw, messages)
  """

  use GenServer

  alias AgentSea.Gateway.CircuitBreaker

  defmodule Provider do
    @moduledoc "A configured provider candidate."
    @enforce_keys [:name, :module, :model]
    defstruct [:name, :module, :model, opts: []]

    @type t :: %__MODULE__{
            name: term(),
            module: module(),
            model: String.t(),
            opts: keyword()
          }
  end

  defmodule Config do
    @moduledoc "Gateway configuration."
    @enforce_keys [:providers]
    defstruct providers: [], strategy: AgentSea.Gateway.Router.Failover

    @type t :: %__MODULE__{providers: [Provider.t()], strategy: module()}
  end

  # --- Client API ---

  def start_link(%Config{} = config, opts \\ []) do
    GenServer.start_link(__MODULE__, config, opts)
  end

  @doc """
  Route a completion. Options: `:exclude` (provider names to skip). Returns
  `{:ok, response, provider_name}` or `{:error, :all_providers_unavailable}`.
  """
  @spec completion(GenServer.server(), [AgentSea.Provider.message()], keyword()) ::
          {:ok, AgentSea.Response.t(), term()} | {:error, :all_providers_unavailable}
  def completion(gateway, messages, opts \\ []) do
    ctx = %{exclude: Keyword.get(opts, :exclude, [])}
    candidates = GenServer.call(gateway, {:plan, ctx})
    try_candidates(candidates, gateway, messages, 0)
  end

  @doc """
  Route a streaming completion. Picks the first available provider (in strategy
  order) that implements `c:AgentSea.Provider.stream/2` and returns its lazy
  event stream. There is no mid-stream failover (a stream can't be replayed).

  Returns `{:ok, stream, provider_name}` or an error.
  """
  @spec stream(GenServer.server(), [AgentSea.Provider.message()], keyword()) ::
          {:ok, Enumerable.t(), term()} | {:error, term()}
  def stream(gateway, messages, opts \\ []) do
    ctx = %{exclude: Keyword.get(opts, :exclude, [])}

    case GenServer.call(gateway, {:plan, ctx}) do
      [] ->
        {:error, :all_providers_unavailable}

      candidates ->
        case Enum.find(candidates, &streamable?/1) do
          nil ->
            {:error, :no_streaming_provider}

          candidate ->
            call_opts = Keyword.merge(candidate.opts || [], model: candidate.model)
            {:ok, candidate.module.stream(messages, call_opts), candidate.name}
        end
    end
  end

  defp streamable?(candidate) do
    Code.ensure_loaded?(candidate.module) and
      function_exported?(candidate.module, :stream, 2)
  end

  @doc "Current per-provider health (latency EMA + call/error counts)."
  def health(gateway), do: GenServer.call(gateway, :health)

  # --- Server ---

  @impl true
  def init(%Config{} = config) do
    Enum.each(config.providers, fn p -> CircuitBreaker.ensure(p.name) end)
    health = :ets.new(:agentsea_gateway_health, [:set, :private])
    {:ok, %{config: config, health: health, rr_counter: 0}}
  end

  @impl true
  def handle_call({:plan, ctx}, _from, state) do
    available =
      Enum.reject(
        state.config.providers,
        &(&1.name in ctx.exclude or CircuitBreaker.ask(&1.name) == :blown)
      )

    ordered =
      state.config.strategy.order(available, %{
        counter: state.rr_counter,
        health: health_map(state.health)
      })

    {:reply, ordered, %{state | rr_counter: state.rr_counter + 1}}
  end

  def handle_call(:health, _from, state), do: {:reply, health_map(state.health), state}

  @impl true
  def handle_cast({:record, name, outcome, latency_ms}, state) do
    update_health(state.health, name, outcome, latency_ms)
    if outcome == :error, do: CircuitBreaker.melt(name)
    {:noreply, state}
  end

  # --- Failover loop (runs in the caller process) ---

  defp try_candidates([], _gateway, _messages, attempts) do
    :telemetry.execute(
      [:agentsea, :gateway, :route, :stop],
      %{attempts: attempts},
      %{provider: nil, outcome: :error}
    )

    {:error, :all_providers_unavailable}
  end

  defp try_candidates([candidate | rest], gateway, messages, attempts) do
    started = System.monotonic_time()
    call_opts = Keyword.merge(candidate.opts || [], model: candidate.model)

    case candidate.module.complete(messages, call_opts) do
      {:ok, response} ->
        latency = elapsed_ms(started)
        GenServer.cast(gateway, {:record, candidate.name, :ok, latency})

        :telemetry.execute(
          [:agentsea, :gateway, :route, :stop],
          %{attempts: attempts + 1, latency_ms: latency},
          %{provider: candidate.name, outcome: :ok}
        )

        {:ok, response, candidate.name}

      {:error, _reason} ->
        GenServer.cast(gateway, {:record, candidate.name, :error, elapsed_ms(started)})
        try_candidates(rest, gateway, messages, attempts + 1)
    end
  end

  # --- Health helpers (run in the gateway process) ---

  defp health_map(health), do: Map.new(:ets.tab2list(health))

  defp update_health(health, name, outcome, latency_ms) do
    current =
      case :ets.lookup(health, name) do
        [{^name, data}] -> data
        [] -> %{latency_ms: nil, calls: 0, errors: 0}
      end

    ema =
      case current.latency_ms do
        nil -> latency_ms
        prev -> round(prev * 0.7 + latency_ms * 0.3)
      end

    :ets.insert(
      health,
      {name,
       %{
         latency_ms: ema,
         calls: current.calls + 1,
         errors: current.errors + if(outcome == :error, do: 1, else: 0)
       }}
    )
  end

  defp elapsed_ms(started),
    do: System.convert_time_unit(System.monotonic_time() - started, :native, :millisecond)
end
