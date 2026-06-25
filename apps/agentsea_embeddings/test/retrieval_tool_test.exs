defmodule AgentSea.Embeddings.RetrievalToolTest do
  use ExUnit.Case, async: true

  alias AgentSea.Embeddings
  alias AgentSea.Embeddings.RetrievalTool
  alias AgentSea.VectorStore.Memory
  alias AgentSea.Embedder.Hashing

  setup do
    store = start_supervised!(Memory)
    handle = Embeddings.new(store_mod: Memory, store: store, embedder: Hashing)

    Embeddings.index(handle, [
      %{id: "refund", text: "refund policy allows returns within thirty days"},
      %{id: "hours", text: "store opening hours are weekdays only"}
    ])

    {:ok, handle: handle}
  end

  test "retrieves passages relevant to the query", %{handle: handle} do
    assert {:ok, result} =
             RetrievalTool.run(%{"query" => "what is the refund policy"}, %{embeddings: handle})

    assert result =~ "refund policy allows returns"
  end

  test "errors when no embeddings handle is in context" do
    assert {:error, :no_embeddings_in_context} = RetrievalTool.run(%{"query" => "x"}, %{})
  end

  test "errors on a missing query", %{handle: handle} do
    assert {:error, :missing_query} = RetrievalTool.run(%{}, %{embeddings: handle})
  end

  test "advertises an AgentSea.Tool surface" do
    assert RetrievalTool.name() == "search_knowledge"
    assert is_binary(RetrievalTool.description())
    assert Keyword.has_key?(RetrievalTool.schema(), :query)
  end
end
