defmodule AgentSea.VectorStore.MemoryTest do
  use ExUnit.Case, async: true

  alias AgentSea.VectorStore.Memory

  setup do
    store = start_supervised!(Memory)
    {:ok, store: store}
  end

  test "upsert, count, and delete", %{store: store} do
    assert Memory.count(store) == 0
    :ok = Memory.upsert(store, [%{id: "a", vector: [1.0, 0.0]}, %{id: "b", vector: [0.0, 1.0]}])
    assert Memory.count(store) == 2

    # Upsert with the same id replaces.
    :ok = Memory.upsert(store, [%{id: "a", vector: [0.5, 0.5]}])
    assert Memory.count(store) == 2

    :ok = Memory.delete(store, ["a"])
    assert Memory.count(store) == 1
  end

  test "query returns the nearest records by cosine similarity", %{store: store} do
    Memory.upsert(store, [
      %{id: "x", vector: [1.0, 0.0], text: "x"},
      %{id: "y", vector: [0.0, 1.0], text: "y"},
      %{id: "z", vector: [0.9, 0.1], text: "z"}
    ])

    hits = Memory.query(store, [1.0, 0.0], 2)
    assert Enum.map(hits, & &1.id) == ["x", "z"]
    assert hd(hits).score >= 0.99
  end

  test "query honors a metadata filter", %{store: store} do
    Memory.upsert(store, [
      %{id: "doc1", vector: [1.0, 0.0], metadata: %{lang: "en"}},
      %{id: "doc2", vector: [1.0, 0.0], metadata: %{lang: "fr"}}
    ])

    hits = Memory.query(store, [1.0, 0.0], 5, filter: &(&1[:lang] == "fr"))
    assert Enum.map(hits, & &1.id) == ["doc2"]
  end
end
