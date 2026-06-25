defmodule AgentSea.VectorStore.Pinecone do
  @moduledoc """
  A [Pinecone](https://pinecone.io) `AgentSea.VectorStore` over its data-plane
  REST API (`Req`) — a managed/remote store alongside the in-memory, pgvector,
  and Qdrant stores.

  The "store" is a config map (index host + api key + optional namespace). Record
  `:text` rides in the point metadata under `"text"` (Pinecone metadata is flat),
  and is split back out on read. Index *creation* is a control-plane concern
  (Pinecone console / control API) — this adapter covers the data plane.

  Per the behaviour, callbacks raise on transport/API errors.

  ## Setup

      store = AgentSea.VectorStore.Pinecone.store(host: "https://my-index-xxxx.svc.pinecone.io")
      AgentSea.Embeddings.new(store_mod: AgentSea.VectorStore.Pinecone, store: store, embedder: ...)
  """

  @behaviour AgentSea.VectorStore

  @type store :: %{
          host: String.t(),
          api_key: String.t() | nil,
          namespace: String.t(),
          adapter: (... -> any()) | nil
        }

  @doc "Build a store. Options: `:host` (required), `:api_key`, `:namespace`, `:adapter`."
  @spec store(keyword()) :: store()
  def store(opts) do
    %{
      host: Keyword.fetch!(opts, :host),
      api_key: opts[:api_key] || System.get_env("PINECONE_API_KEY"),
      namespace: Keyword.get(opts, :namespace, ""),
      adapter: opts[:adapter]
    }
  end

  # --- VectorStore behaviour ---

  @impl true
  def upsert(store, records) do
    vectors =
      Enum.map(records, fn record ->
        %{id: to_string(record.id), values: record.vector, metadata: metadata(record)}
      end)

    _ = request!(store, "/vectors/upsert", %{vectors: vectors, namespace: store.namespace})
    :ok
  end

  @impl true
  def query(store, vector, k, opts) do
    body = %{vector: vector, topK: k, includeMetadata: true, namespace: store.namespace}
    body = if opts[:filter], do: Map.put(body, :filter, opts[:filter]), else: body

    result = request!(store, "/query", body)
    Enum.map(result["matches"] || [], &to_hit/1)
  end

  @impl true
  def delete(store, ids) do
    body = %{ids: Enum.map(ids, &to_string/1), namespace: store.namespace}
    _ = request!(store, "/vectors/delete", body)
    :ok
  end

  @impl true
  def count(store) do
    result = request!(store, "/describe_index_stats", %{})
    result["totalVectorCount"] || 0
  end

  # --- Helpers ---

  defp metadata(record) do
    base = Map.get(record, :metadata, %{})

    case Map.get(record, :text) do
      nil -> base
      text -> Map.put(base, "text", text)
    end
  end

  defp to_hit(match) do
    md = match["metadata"] || %{}
    %{id: match["id"], score: match["score"], text: md["text"], metadata: Map.delete(md, "text")}
  end

  defp request!(store, path, body) do
    case request(store, path, body) do
      {:ok, result} -> result
      {:error, reason} -> raise "Pinecone POST #{path} failed: #{inspect(reason)}"
    end
  end

  defp request(store, path, body) do
    req =
      [base_url: store.host, headers: headers(store)]
      |> maybe_put(:adapter, store.adapter)
      |> Req.new()

    case Req.post(req, url: path, json: body) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp headers(%{api_key: nil}), do: []
  defp headers(%{api_key: key}), do: [{"api-key", key}]

  defp maybe_put(kw, _key, nil), do: kw
  defp maybe_put(kw, key, value), do: Keyword.put(kw, key, value)
end
