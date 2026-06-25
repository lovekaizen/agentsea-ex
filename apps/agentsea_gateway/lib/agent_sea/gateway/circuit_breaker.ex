defmodule AgentSea.Gateway.CircuitBreaker do
  @moduledoc """
  Per-provider circuit breaker on top of the battle-tested `:fuse` library.

  Each provider gets a fuse. A failed call `melt/1`s it; once it has melted past
  its tolerance within the window the fuse is "blown" and the gateway skips that
  provider until it resets. We don't hand-roll the closed/open/half-open state
  machine — `:fuse` already has it.
  """

  # Tolerate 1 melt per 10s; the 2nd melt within the window blows the fuse.
  # Auto-resets 30s after blowing.
  @fuse_options {{:standard, 1, 10_000}, {:reset, 30_000}}

  @doc "Install the provider's fuse if it isn't already present."
  @spec ensure(term()) :: :ok | :reset | {:error, term()}
  def ensure(name) do
    case :fuse.ask(fuse_name(name), :sync) do
      :ok -> :ok
      :blown -> :ok
      {:error, :not_found} -> :fuse.install(fuse_name(name), @fuse_options)
    end
  end

  @doc "Whether the provider's circuit is currently usable."
  @spec ask(term()) :: :ok | :blown
  def ask(name) do
    case :fuse.ask(fuse_name(name), :sync) do
      :ok -> :ok
      :blown -> :blown
      {:error, :not_found} -> :ok
    end
  end

  @doc "Record a failure against the provider's fuse."
  @spec melt(term()) :: :ok
  def melt(name), do: :fuse.melt(fuse_name(name))

  @doc "Remove the provider's fuse (e.g. on gateway shutdown / test cleanup)."
  @spec remove(term()) :: :ok
  def remove(name), do: :fuse.remove(fuse_name(name))

  defp fuse_name(name), do: :"agentsea_gateway_fuse_#{name}"
end
