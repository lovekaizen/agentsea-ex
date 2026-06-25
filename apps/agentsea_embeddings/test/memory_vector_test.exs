defmodule AgentSea.Memory.VectorTest do
  use ExUnit.Case, async: false

  alias AgentSea.Embeddings
  alias AgentSea.Embedder.Hashing
  alias AgentSea.Memory.Vector
  alias AgentSea.VectorStore.Memory, as: MemoryStore

  setup do
    store = start_supervised!(MemoryStore)
    handle = Embeddings.new(store_mod: MemoryStore, store: store, embedder: Hashing)
    start_supervised!({Vector, embeddings: handle})
    :ok
  end

  test "save then load returns the conversation messages in order" do
    messages = [
      %{role: :user, content: "what is the refund policy"},
      %{role: :assistant, content: "returns within 30 days"}
    ]

    assert :ok = Vector.save("c1", messages)
    assert Vector.load("c1") == messages
  end

  test "search recalls semantically relevant past messages" do
    Vector.save("c1", [
      %{role: :user, content: "what is the refund policy"},
      %{role: :assistant, content: "the store opens on weekdays only"}
    ])

    assert [%{role: :user, content: "what is the refund policy"} | _] = Vector.search("refund", 1)
  end

  test "clear removes a conversation from load" do
    Vector.save("c1", [%{role: :user, content: "hi"}])
    assert Vector.load("c1") == [%{role: :user, content: "hi"}]
    assert :ok = Vector.clear("c1")
    assert Vector.load("c1") == []
  end

  test "re-saving replaces prior messages (no stale recall)" do
    Vector.save("c1", [%{role: :user, content: "first version about apples"}])
    Vector.save("c1", [%{role: :user, content: "second version about oranges"}])

    assert Vector.load("c1") == [%{role: :user, content: "second version about oranges"}]
    assert [%{content: "second version about oranges"}] = Vector.search("oranges", 5)
  end
end
