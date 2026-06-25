defmodule AgentSea.Ingest.PipelineTest do
  use ExUnit.Case, async: false

  alias AgentSea.Ingest
  alias AgentSea.Ingest.Pipeline
  alias AgentSea.VectorStore.Memory
  alias AgentSea.Embedder.Hashing
  alias AgentSea.Embeddings

  setup do
    store = start_supervised!(Memory)
    name = :"ingest_#{System.unique_integer([:positive])}"

    start_supervised!(%{
      id: name,
      start:
        {Pipeline, :start_link,
         [[name: name, embedder: Hashing, store_mod: Memory, store: store, batch_size: 100]]}
    })

    {:ok, store: store, pipeline: name}
  end

  test "embeds and stores pushed chunks", %{store: store, pipeline: pipeline} do
    chunks =
      Ingest.chunk_documents(
        [%{id: "doc", text: String.duplicate("alpha beta gamma delta ", 40)}],
        size: 30,
        overlap: 5
      )

    assert length(chunks) > 1

    ref = Broadway.test_batch(pipeline, chunks)
    assert_receive {:ack, ^ref, successful, []}, 2000

    assert length(successful) == length(chunks)
    assert Memory.count(store) == length(chunks)
  end

  test "ingested chunks are retrievable by semantic search", %{store: store, pipeline: pipeline} do
    chunks = [
      %{id: "c0", text: "refund policy allows returns within thirty days", metadata: %{}},
      %{id: "c1", text: "store opening hours are weekdays only", metadata: %{}}
    ]

    ref = Broadway.test_batch(pipeline, chunks)
    assert_receive {:ack, ^ref, _successful, []}, 2000

    handle = Embeddings.new(store_mod: Memory, store: store, embedder: Hashing)
    assert [top | _] = Embeddings.search(handle, "refund policy", 2)
    assert top.id == "c0"
  end
end
