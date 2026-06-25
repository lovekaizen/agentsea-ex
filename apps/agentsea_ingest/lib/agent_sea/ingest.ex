defmodule AgentSea.Ingest do
  @moduledoc """
  Document ingestion. `chunk_documents/2` turns documents into chunk messages
  (the unit the `AgentSea.Ingest.Pipeline` Broadway topology embeds and stores).

  A document is a map with `:id`, `:text`, and optional `:metadata`. Each chunk
  carries `id` "<doc_id>-<n>" and inherits the document's metadata plus
  `:source` (the document id).
  """

  alias AgentSea.Ingest.Chunker

  @type document :: %{required(:id) => term(), required(:text) => String.t(), optional(:metadata) => map()}
  @type chunk :: %{id: String.t(), text: String.t(), metadata: map()}

  @spec chunk_documents([document()], keyword()) :: [chunk()]
  def chunk_documents(documents, opts \\ []) do
    Enum.flat_map(documents, fn document ->
      id = Map.fetch!(document, :id)
      metadata = Map.get(document, :metadata, %{})

      document
      |> Map.fetch!(:text)
      |> Chunker.chunk(opts)
      |> Enum.with_index()
      |> Enum.map(fn {text, index} ->
        %{id: "#{id}-#{index}", text: text, metadata: Map.put(metadata, :source, id)}
      end)
    end)
  end
end
