defmodule AgentSea.VectorStore.Qdrant do
  @moduledoc """
  A [Qdrant](https://qdrant.tech) `AgentSea.VectorStore` over its REST API (`Req`)
  — a managed/remote alternative to the in-memory and pgvector stores.

  The "store" is a config map (base url + collection + optional api key), so it
  drops into `AgentSea.Embeddings` like the others. Similarity is cosine; record
  `:text` and `:metadata` ride along in the point payload.

  Per the behaviour, the callbacks raise on transport/API errors (like the
  pgvector store's `Postgrex.query!`). Note Qdrant point ids must be unsigned
  integers or UUIDs.

  ## Setup

      store = AgentSea.VectorStore.Qdrant.store(url: "http://localhost:6333", collection: "docs")
      :ok = AgentSea.VectorStore.Qdrant.ensure_collection(store, 1536)

      AgentSea.Embeddings.new(store_mod: AgentSea.VectorStore.Qdrant, store: store, embedder: ...)
  """

  @behaviour AgentSea.VectorStore

  @type store :: %{
          url: String.t(),
          collection: String.t(),
          api_key: String.t() | nil,
          adapter: (... -> any()) | nil
        }

  @doc "Build a store. Options: `:collection` (required), `:url`, `:api_key`, `:adapter`."
  @spec store(keyword()) :: store()
  def store(opts) do
    %{
      url: Keyword.get(opts, :url, "http://localhost:6333"),
      collection: Keyword.fetch!(opts, :collection),
      api_key: opts[:api_key],
      adapter: opts[:adapter]
    }
  end

  @doc "Create the collection if absent, with the given vector size and distance (default Cosine)."
  @spec ensure_collection(store(), pos_integer(), keyword()) :: :ok
  def ensure_collection(store, dimensions, opts \\ []) do
    distance = Keyword.get(opts, :distance, "Cosine")
    body = %{vectors: %{size: dimensions, distance: distance}}
    _ = request!(store, :put, "/collections/#{store.collection}", body)
    :ok
  end

  # --- VectorStore behaviour ---

  @impl true
  def upsert(store, records) do
    points =
      Enum.map(records, fn record ->
        %{
          id: record.id,
          vector: record.vector,
          payload: %{
            "text" => Map.get(record, :text),
            "metadata" => Map.get(record, :metadata, %{})
          }
        }
      end)

    _ = request!(store, :put, "/collections/#{store.collection}/points", %{points: points})
    :ok
  end

  @impl true
  def query(store, vector, k, opts) do
    body = %{vector: vector, limit: k, with_payload: true}
    body = if opts[:filter], do: Map.put(body, :filter, opts[:filter]), else: body

    result = request!(store, :post, "/collections/#{store.collection}/points/search", body)
    Enum.map(result["result"] || [], &to_hit/1)
  end

  @impl true
  def delete(store, ids) do
    _ = request!(store, :post, "/collections/#{store.collection}/points/delete", %{points: ids})
    :ok
  end

  @impl true
  def count(store) do
    result =
      request!(store, :post, "/collections/#{store.collection}/points/count", %{exact: true})

    get_in(result, ["result", "count"]) || 0
  end

  # --- HTTP ---

  defp request!(store, method, path, body) do
    case request(store, method, path, body) do
      {:ok, result} ->
        result

      {:error, reason} ->
        raise "Qdrant #{method} #{path} failed: #{inspect(reason)}"
    end
  end

  defp request(store, method, path, body) do
    req =
      [base_url: store.url, headers: headers(store)]
      |> maybe_put(:adapter, store.adapter)
      |> Req.new()

    response =
      case method do
        :put -> Req.put(req, url: path, json: body)
        :post -> Req.post(req, url: path, json: body)
      end

    case response do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp headers(%{api_key: nil}), do: []
  defp headers(%{api_key: key}), do: [{"api-key", key}]

  defp to_hit(%{"id" => id} = point) do
    payload = point["payload"] || %{}
    %{id: id, score: point["score"], text: payload["text"], metadata: payload["metadata"] || %{}}
  end

  defp maybe_put(kw, _key, nil), do: kw
  defp maybe_put(kw, key, value), do: Keyword.put(kw, key, value)
end
