defmodule AgentSea.VectorStore.Memory do
  @moduledoc """
  In-memory vector store backed by a `GenServer`. Brute-force cosine-similarity
  search — fine for tests, small corpora, and demos. Records are keyed by id.
  """

  @behaviour AgentSea.VectorStore
  use GenServer

  # --- Client ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, opts)
  end

  @impl AgentSea.VectorStore
  def upsert(store, records), do: GenServer.call(store, {:upsert, records})

  @impl AgentSea.VectorStore
  def query(store, vector, k, opts \\ []), do: GenServer.call(store, {:query, vector, k, opts})

  @impl AgentSea.VectorStore
  def delete(store, ids), do: GenServer.call(store, {:delete, ids})

  @impl AgentSea.VectorStore
  def count(store), do: GenServer.call(store, :count)

  # --- Server ---

  @impl GenServer
  def init(_), do: {:ok, %{records: %{}}}

  @impl GenServer
  def handle_call({:upsert, records}, _from, state) do
    records =
      Enum.reduce(records, state.records, fn record, acc ->
        Map.put(acc, record.id, normalize_record(record))
      end)

    {:reply, :ok, %{state | records: records}}
  end

  def handle_call({:query, vector, k, opts}, _from, state) do
    filter = Keyword.get(opts, :filter, fn _metadata -> true end)

    hits =
      state.records
      |> Map.values()
      |> Enum.filter(fn record -> filter.(record.metadata) end)
      |> Enum.map(fn record ->
        %{
          id: record.id,
          score: AgentSea.Vector.cosine(vector, record.vector),
          metadata: record.metadata,
          text: record.text
        }
      end)
      |> Enum.sort_by(& &1.score, :desc)
      |> Enum.take(k)

    {:reply, hits, state}
  end

  def handle_call({:delete, ids}, _from, state) do
    {:reply, :ok, %{state | records: Map.drop(state.records, ids)}}
  end

  def handle_call(:count, _from, state) do
    {:reply, map_size(state.records), state}
  end

  defp normalize_record(record) do
    %{
      id: record.id,
      vector: record.vector,
      metadata: Map.get(record, :metadata, %{}),
      text: Map.get(record, :text)
    }
  end
end
