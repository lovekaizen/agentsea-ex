defmodule AgentSea.VectorStore.Postgres do
  @moduledoc """
  A pgvector-backed `AgentSea.VectorStore` over Postgrex — the design's first-
  class production store.

  The "store" is a plain map bundling a Postgrex connection with the table name
  and dimensionality, so it slots into `AgentSea.Embeddings` exactly like the
  in-memory store. Vectors are passed as `$n::vector` text literals (no extra
  type extension needed); similarity is cosine (`<=>`); metadata is `jsonb`.

  ## Setup

      {:ok, conn} = Postgrex.start_link(database: "agentsea", hostname: "localhost")
      store = AgentSea.VectorStore.Postgres.store(conn, table: "embeddings", dimensions: 1536)
      :ok = AgentSea.VectorStore.Postgres.ensure_table(store)

      AgentSea.Embeddings.new(store_mod: AgentSea.VectorStore.Postgres, store: store, embedder: ...)
  """

  @behaviour AgentSea.VectorStore

  @type store :: %{conn: GenServer.server(), table: String.t(), dimensions: pos_integer()}

  @doc "Bundle a Postgrex connection into a store. Options: `:table`, `:dimensions` (required)."
  @spec store(GenServer.server(), keyword()) :: store()
  def store(conn, opts) do
    %{
      conn: conn,
      table: valid_table!(Keyword.get(opts, :table, "agentsea_embeddings")),
      dimensions: Keyword.fetch!(opts, :dimensions)
    }
  end

  @doc "Create the pgvector extension and the embeddings table if absent."
  @spec ensure_table(store()) :: :ok
  def ensure_table(%{conn: conn, table: table, dimensions: dim}) do
    Postgrex.query!(conn, "CREATE EXTENSION IF NOT EXISTS vector", [])

    Postgrex.query!(
      conn,
      "CREATE TABLE IF NOT EXISTS #{table} " <>
        "(id text PRIMARY KEY, embedding vector(#{dim}), text text, metadata jsonb)",
      []
    )

    :ok
  end

  # --- VectorStore behaviour ---

  @impl true
  def upsert(%{conn: conn, table: table}, records) do
    Enum.each(records, fn record ->
      Postgrex.query!(
        conn,
        "INSERT INTO #{table} (id, embedding, text, metadata) " <>
          "VALUES ($1, $2::vector, $3, $4::jsonb) " <>
          "ON CONFLICT (id) DO UPDATE SET " <>
          "embedding = EXCLUDED.embedding, text = EXCLUDED.text, metadata = EXCLUDED.metadata",
        [
          to_string(record.id),
          vector_literal(record.vector),
          Map.get(record, :text),
          Jason.encode!(Map.get(record, :metadata, %{}))
        ]
      )
    end)

    :ok
  end

  @impl true
  def query(%{conn: conn, table: table}, vector, k, opts) do
    literal = vector_literal(vector)
    select = "SELECT id, text, metadata::text, 1 - (embedding <=> $1::vector) AS score FROM #{table}"
    order = "ORDER BY embedding <=> $1::vector LIMIT"

    {sql, params} =
      case Keyword.get(opts, :where) do
        nil ->
          {"#{select} #{order} $2", [literal, k]}

        where when is_map(where) ->
          {"#{select} WHERE metadata @> $2::jsonb #{order} $3", [literal, Jason.encode!(where), k]}
      end

    %{rows: rows} = Postgrex.query!(conn, sql, params)
    Enum.map(rows, &row_to_hit/1)
  end

  @impl true
  def delete(%{conn: conn, table: table}, ids) do
    Postgrex.query!(conn, "DELETE FROM #{table} WHERE id = ANY($1)", [Enum.map(ids, &to_string/1)])
    :ok
  end

  @impl true
  def count(%{conn: conn, table: table}) do
    %{rows: [[n]]} = Postgrex.query!(conn, "SELECT count(*) FROM #{table}", [])
    n
  end

  # --- Helpers (pure, unit-tested) ---

  @doc "Encode a vector as a pgvector text literal, e.g. `[1.0,2.0,3.0]`."
  @spec vector_literal([number()]) :: String.t()
  def vector_literal(vector), do: "[" <> Enum.map_join(vector, ",", &to_string/1) <> "]"

  @doc "Validate a table identifier (guards against SQL injection via the name)."
  @spec valid_table!(String.t()) :: String.t()
  def valid_table!(table) do
    if Regex.match?(~r/\A[a-zA-Z_][a-zA-Z0-9_]*\z/, table) do
      table
    else
      raise ArgumentError, "invalid table name: #{inspect(table)}"
    end
  end

  defp row_to_hit([id, text, metadata_json, score]) do
    %{id: id, text: text, metadata: decode_metadata(metadata_json), score: score}
  end

  defp decode_metadata(nil), do: %{}

  defp decode_metadata(json) do
    case Jason.decode(json) do
      {:ok, map} -> map
      _ -> %{}
    end
  end
end
