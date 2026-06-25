defmodule AgentSea.VectorStore do
  @moduledoc """
  Stores vectors and answers nearest-neighbour queries. Adapters: the in-memory
  `AgentSea.VectorStore.Memory` and, in future, pgvector (first-class via Ecto)
  or remote stores (Pinecone/Qdrant) over HTTP.
  """

  @type store :: GenServer.server()
  @type record :: %{
          required(:id) => term(),
          required(:vector) => [float()],
          optional(:metadata) => map(),
          optional(:text) => String.t() | nil
        }
  @type hit :: %{id: term(), score: float(), metadata: map(), text: String.t() | nil}

  @callback upsert(store(), [record()]) :: :ok
  @callback query(store(), [float()], k :: pos_integer(), opts :: keyword()) :: [hit()]
  @callback delete(store(), [term()]) :: :ok
  @callback count(store()) :: non_neg_integer()
end
