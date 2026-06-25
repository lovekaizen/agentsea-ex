defmodule AgentSea.Embeddings.RagTest do
  # async: false — the agent runs in its own process and consumes Mox
  # expectations in global mode.
  use ExUnit.Case, async: false

  import Mox

  alias AgentSea.{Agent, Response, ToolCall}
  alias AgentSea.Embeddings
  alias AgentSea.Embeddings.{RetrievalTool, MockProvider}
  alias AgentSea.VectorStore.Memory
  alias AgentSea.Embedder.Hashing

  setup :set_mox_global
  setup :verify_on_exit!

  test "agent retrieves from the knowledge base via the tool, then answers" do
    store = start_supervised!(Memory)
    handle = Embeddings.new(store_mod: Memory, store: store, embedder: Hashing)

    Embeddings.index(handle, [
      %{id: "refund", text: "refund policy allows returns within thirty days"},
      %{id: "hours", text: "store opening hours are weekdays only"}
    ])

    # 1st completion: the model asks to search. 2nd: it answers from the result.
    MockProvider
    |> expect(:complete, fn _messages, _opts ->
      {:ok,
       %Response{
         stop_reason: :tool_use,
         tool_calls: [
           %ToolCall{
             id: "t1",
             name: "search_knowledge",
             arguments: %{"query" => "what is the refund policy"}
           }
         ]
       }}
    end)
    |> expect(:complete, fn messages, _opts ->
      # The retrieved passage must have been fed back before the model answers.
      tool_message = Enum.find(messages, &(&1.role == :tool))
      assert tool_message.content =~ "refund policy allows returns"

      {:ok, %Response{content: "You can return items within 30 days."}}
    end)

    config = %Agent.Config{
      name: :rag,
      model: "m",
      provider: {MockProvider, []},
      tools: [RetrievalTool]
    }

    agent = start_supervised!({Agent, config})

    assert {:ok, %Response{content: "You can return items within 30 days."}} =
             Agent.run(agent, "refund policy?", %{embeddings: handle})
  end
end
