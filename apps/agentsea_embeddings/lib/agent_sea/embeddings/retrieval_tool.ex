defmodule AgentSea.Embeddings.RetrievalTool do
  @moduledoc """
  An `AgentSea.Tool` that lets an agent search a knowledge base — the retrieval
  half of RAG.

  It reads the `AgentSea.Embeddings` handle from the agent's execution context
  (`ctx.embeddings`), so the same tool module works against any store/embedder
  without per-instance config. Add it to an agent's `tools` and pass the handle
  when running:

      Agent.run(agent, "what is the refund policy?", %{embeddings: handle})
  """

  @behaviour AgentSea.Tool

  @default_k 3

  @impl true
  def name, do: "search_knowledge"

  @impl true
  def description,
    do:
      "Search the knowledge base for passages relevant to a query. " <>
        "Returns the most relevant passages to ground your answer."

  @impl true
  def schema do
    [
      query: [type: :string, required: true],
      k: [type: :integer]
    ]
  end

  @impl true
  def run(args, ctx) do
    case Map.get(ctx, :embeddings) do
      %AgentSea.Embeddings{} = handle ->
        query = arg(args, :query)
        k = arg(args, :k) || @default_k

        if is_binary(query) and query != "" do
          {:ok, format(AgentSea.Embeddings.search(handle, query, k))}
        else
          {:error, :missing_query}
        end

      _ ->
        {:error, :no_embeddings_in_context}
    end
  end

  defp arg(args, key), do: Map.get(args, to_string(key)) || Map.get(args, key)

  defp format([]), do: "No relevant passages found."

  defp format(hits) do
    hits
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {hit, i} ->
      "#{i}. (score #{Float.round(hit.score, 3)}) #{hit.text}"
    end)
  end
end
