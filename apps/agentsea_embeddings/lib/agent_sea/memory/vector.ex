defmodule AgentSea.Memory.Vector do
  @moduledoc """
  Vector-backed conversation memory: messages are embedded and indexed, so
  `search/2` recalls the most *relevant* past messages (not just the most
  recent). Wraps an `AgentSea.Embeddings` handle (any embedder + vector store).

  `load/1` still returns a conversation's messages in order; `search/2` does
  semantic retrieval across stored memory. A singleton (like
  `AgentSea.Memory.Buffer`); start it with an `:embeddings` handle.
  """

  @behaviour AgentSea.Memory
  use GenServer

  alias AgentSea.Embeddings

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl AgentSea.Memory
  def save(conversation_id, messages),
    do: GenServer.call(__MODULE__, {:save, conversation_id, messages})

  @impl AgentSea.Memory
  def load(conversation_id), do: GenServer.call(__MODULE__, {:load, conversation_id})

  @impl AgentSea.Memory
  def clear(conversation_id), do: GenServer.call(__MODULE__, {:clear, conversation_id})

  @impl AgentSea.Memory
  def search(query, limit), do: GenServer.call(__MODULE__, {:search, query, limit})

  # --- Server ---

  @impl GenServer
  def init(opts) do
    {:ok, %{embeddings: Keyword.fetch!(opts, :embeddings), store: %{}}}
  end

  @impl GenServer
  def handle_call({:save, id, messages}, _from, state) do
    state = delete_conversation(state, id)

    entries =
      Enum.with_index(messages, fn message, index ->
        %{
          id: "#{id}:#{index}",
          text: to_string(message.content),
          metadata: %{"conv_id" => id, "role" => to_string(message.role)}
        }
      end)

    Embeddings.index(state.embeddings, entries)
    entry = %{messages: messages, ids: Enum.map(entries, & &1.id)}
    {:reply, :ok, %{state | store: Map.put(state.store, id, entry)}}
  end

  def handle_call({:load, id}, _from, state) do
    messages = with %{messages: messages} <- Map.get(state.store, id), do: messages
    {:reply, messages || [], state}
  end

  def handle_call({:clear, id}, _from, state) do
    {:reply, :ok, delete_conversation(state, id)}
  end

  def handle_call({:search, query, limit}, _from, state) do
    messages =
      case Embeddings.search(state.embeddings, query, limit) do
        hits when is_list(hits) -> Enum.map(hits, &hit_to_message/1)
        {:error, _reason} -> []
      end

    {:reply, messages, state}
  end

  # --- Helpers ---

  defp delete_conversation(state, id) do
    case Map.get(state.store, id) do
      %{ids: ids} ->
        handle = state.embeddings
        handle.store_mod.delete(handle.store, ids)
        %{state | store: Map.delete(state.store, id)}

      nil ->
        state
    end
  end

  defp hit_to_message(hit) do
    %{role: role(get_in(hit, [:metadata, "role"])), content: hit.text}
  end

  defp role("assistant"), do: :assistant
  defp role("system"), do: :system
  defp role("tool"), do: :tool
  defp role(_), do: :user
end
