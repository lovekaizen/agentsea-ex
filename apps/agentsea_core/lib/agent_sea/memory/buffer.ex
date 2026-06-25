defmodule AgentSea.Memory.Buffer do
  @moduledoc """
  A simple in-memory conversation buffer backed by a `GenServer`.

  Stores a rolling window of messages per conversation id. A single buffer
  process serves many conversations (keyed by id); pass `:max_messages` to cap
  the window per conversation.
  """

  @behaviour AgentSea.Memory
  use GenServer

  # --- Client ---

  @doc "Start a buffer. Options: `:name` (default `#{inspect(__MODULE__)}`), `:max_messages`."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl AgentSea.Memory
  def save(conversation_id, messages),
    do: GenServer.call(__MODULE__, {:save, conversation_id, messages})

  @impl AgentSea.Memory
  def load(conversation_id),
    do: GenServer.call(__MODULE__, {:load, conversation_id})

  @impl AgentSea.Memory
  def clear(conversation_id),
    do: GenServer.call(__MODULE__, {:clear, conversation_id})

  @doc "Append messages to a conversation (respecting the window cap)."
  def append(conversation_id, messages) when is_list(messages),
    do: GenServer.call(__MODULE__, {:append, conversation_id, messages})

  # --- Server ---

  @impl GenServer
  def init(opts) do
    {:ok, %{max: Keyword.get(opts, :max_messages), store: %{}}}
  end

  @impl GenServer
  def handle_call({:save, id, messages}, _from, state) do
    {:reply, :ok, put(state, id, messages)}
  end

  def handle_call({:append, id, messages}, _from, state) do
    existing = Map.get(state.store, id, [])
    {:reply, :ok, put(state, id, existing ++ messages)}
  end

  def handle_call({:load, id}, _from, state) do
    {:reply, Map.get(state.store, id, []), state}
  end

  def handle_call({:clear, id}, _from, state) do
    {:reply, :ok, %{state | store: Map.delete(state.store, id)}}
  end

  defp put(%{max: max} = state, id, messages) do
    windowed = if is_integer(max), do: Enum.take(messages, -max), else: messages
    %{state | store: Map.put(state.store, id, windowed)}
  end
end
