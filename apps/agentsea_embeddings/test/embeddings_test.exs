defmodule AgentSea.EmbeddingsTest do
  use ExUnit.Case, async: true

  alias AgentSea.Embeddings
  alias AgentSea.VectorStore.Memory
  alias AgentSea.Embedder.Hashing

  setup do
    store = start_supervised!(Memory)

    handle =
      Embeddings.new(store_mod: Memory, store: store, embedder: Hashing)

    {:ok, handle: handle}
  end

  test "indexes documents and semantic-searches by text", %{handle: handle} do
    :ok =
      Embeddings.index(handle, [
        %{id: "cat", text: "the cat sat on the warm mat"},
        %{id: "finance", text: "quarterly revenue grew twelve percent"},
        %{id: "dog", text: "the dog ran across the green park"}
      ])

    assert [top | _] = Embeddings.search(handle, "where did the cat sit", 3)
    assert top.id == "cat"
    assert top.score > 0.0
  end

  test "carries metadata through and supports filtering", %{handle: handle} do
    :ok =
      Embeddings.index(handle, [
        %{id: "a", text: "machine learning models", metadata: %{topic: "ml"}},
        %{id: "b", text: "machine learning pipelines", metadata: %{topic: "ops"}}
      ])

    hits = Embeddings.search(handle, "machine learning", 5, filter: &(&1[:topic] == "ops"))
    assert Enum.map(hits, & &1.id) == ["b"]
    assert hd(hits).metadata == %{topic: "ops"}
  end
end
