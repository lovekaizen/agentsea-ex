defmodule AgentSea.Ingest.ChunkerTest do
  use ExUnit.Case, async: true

  alias AgentSea.Ingest.Chunker
  alias AgentSea.Ingest

  test "short text is a single chunk" do
    assert Chunker.chunk("just a few words", size: 100) == ["just a few words"]
  end

  test "empty text yields no chunks" do
    assert Chunker.chunk("", size: 100) == []
    assert Chunker.chunk("   ", size: 100) == []
  end

  test "splits into overlapping windows" do
    words = Enum.map_join(1..10, " ", &"w#{&1}")
    chunks = Chunker.chunk(words, size: 4, overlap: 2)

    # step = size - overlap = 2; the final full window covers w7..w10.
    assert chunks == [
             "w1 w2 w3 w4",
             "w3 w4 w5 w6",
             "w5 w6 w7 w8",
             "w7 w8 w9 w10"
           ]
  end

  test "chunk_documents emits ids and source metadata" do
    docs = [%{id: "doc1", text: "a b c d e f", metadata: %{lang: "en"}}]
    chunks = Ingest.chunk_documents(docs, size: 3, overlap: 1)

    assert Enum.map(chunks, & &1.id) == ["doc1-0", "doc1-1", "doc1-2"]
    assert Enum.all?(chunks, &(&1.metadata.source == "doc1"))
    assert Enum.all?(chunks, &(&1.metadata.lang == "en"))
  end
end
