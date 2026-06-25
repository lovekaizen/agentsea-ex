defmodule AgentSea.Embeddings do
  @moduledoc """
  Ties an `AgentSea.Embedder` to an `AgentSea.VectorStore`: embed-and-index text
  documents, then semantic-search by text.

  ## Example

      {:ok, store} = AgentSea.VectorStore.Memory.start_link()

      handle =
        AgentSea.Embeddings.new(
          store_mod: AgentSea.VectorStore.Memory,
          store: store,
          embedder: AgentSea.Embedder.Hashing
        )

      AgentSea.Embeddings.index(handle, [
        %{id: "a", text: "the cat sat on the mat"},
        %{id: "b", text: "quarterly revenue grew 12%"}
      ])

      [%{id: "a"} | _] = AgentSea.Embeddings.search(handle, "where is the cat", 1)
  """

  @enforce_keys [:store_mod, :store, :embedder]
  defstruct [:store_mod, :store, :embedder, embed_opts: []]

  @type t :: %__MODULE__{
          store_mod: module(),
          store: GenServer.server(),
          embedder: module(),
          embed_opts: keyword()
        }

  @type entry :: %{required(:id) => term(), required(:text) => String.t(), optional(:metadata) => map()}

  @doc "Build a handle bundling a store + embedder."
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      store_mod: Keyword.fetch!(opts, :store_mod),
      store: Keyword.fetch!(opts, :store),
      embedder: Keyword.fetch!(opts, :embedder),
      embed_opts: Keyword.get(opts, :embed_opts, [])
    }
  end

  @doc "Embed each entry's text and upsert it into the store."
  @spec index(t(), [entry()]) :: :ok | {:error, term()}
  def index(%__MODULE__{} = handle, entries) do
    texts = Enum.map(entries, &Map.fetch!(&1, :text))

    case handle.embedder.embed(texts, handle.embed_opts) do
      {:ok, vectors} ->
        records =
          entries
          |> Enum.zip(vectors)
          |> Enum.map(fn {entry, vector} ->
            %{
              id: Map.fetch!(entry, :id),
              vector: vector,
              metadata: Map.get(entry, :metadata, %{}),
              text: Map.fetch!(entry, :text)
            }
          end)

        handle.store_mod.upsert(handle.store, records)

      {:error, _reason} = error ->
        error
    end
  end

  @doc "Embed the query text and return the `k` most similar records."
  @spec search(t(), String.t(), pos_integer(), keyword()) ::
          [AgentSea.VectorStore.hit()] | {:error, term()}
  def search(%__MODULE__{} = handle, query, k, opts \\ []) do
    case handle.embedder.embed([query], handle.embed_opts) do
      {:ok, [vector]} -> handle.store_mod.query(handle.store, vector, k, opts)
      {:error, _reason} = error -> error
    end
  end
end
