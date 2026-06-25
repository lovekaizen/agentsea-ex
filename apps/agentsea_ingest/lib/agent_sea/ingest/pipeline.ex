defmodule AgentSea.Ingest.Pipeline do
  @moduledoc """
  A `Broadway` pipeline that embeds chunk messages and upserts them into a
  vector store. Concurrency, batching, backpressure, and retries are Broadway
  settings — there is no hand-rolled scheduler (this is the design's
  "EvaluationPipeline parallelism bug is structurally impossible" point).

  Each message's `data` is a chunk `%{id, text, metadata}` (see
  `AgentSea.Ingest.chunk_documents/2`). Messages are collected into batches,
  embedded in a single call, then upserted.

  ## Starting

      AgentSea.Ingest.Pipeline.start_link(
        name: MyPipeline,
        embedder: AgentSea.Embedder.Hashing,
        store_mod: AgentSea.VectorStore.Memory,
        store: store_pid
      )

  The default producer is `Broadway.DummyProducer` (drive it with
  `Broadway.test_message/3` or `Broadway.test_batch/3`). For production, pass a
  real `:producer` that emits chunk messages.
  """

  use Broadway

  alias Broadway.Message

  def start_link(opts) do
    context = %{
      embedder: Keyword.fetch!(opts, :embedder),
      store_mod: Keyword.fetch!(opts, :store_mod),
      store: Keyword.fetch!(opts, :store)
    }

    Broadway.start_link(__MODULE__,
      name: Keyword.fetch!(opts, :name),
      context: context,
      producer: [module: Keyword.get(opts, :producer, {Broadway.DummyProducer, []})],
      processors: [default: [concurrency: Keyword.get(opts, :processor_concurrency, 2)]],
      batchers: [
        default: [
          concurrency: 1,
          batch_size: Keyword.get(opts, :batch_size, 10),
          batch_timeout: Keyword.get(opts, :batch_timeout, 100)
        ]
      ]
    )
  end

  @impl true
  def handle_message(_processor, message, _context) do
    # Nothing per-message; batch everything so embedding happens in bulk.
    Message.put_batcher(message, :default)
  end

  @impl true
  def handle_batch(:default, messages, _batch_info, context) do
    chunks = Enum.map(messages, & &1.data)
    texts = Enum.map(chunks, & &1.text)

    case context.embedder.embed(texts, []) do
      {:ok, vectors} ->
        records =
          chunks
          |> Enum.zip(vectors)
          |> Enum.map(fn {chunk, vector} ->
            %{
              id: chunk.id,
              vector: vector,
              text: chunk.text,
              metadata: Map.get(chunk, :metadata, %{})
            }
          end)

        context.store_mod.upsert(context.store, records)
        messages

      {:error, reason} ->
        Enum.map(messages, &Message.failed(&1, {:embed_error, reason}))
    end
  end
end
