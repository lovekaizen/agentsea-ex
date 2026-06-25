defmodule AgentSea.VectorStore.PineconeTest do
  use ExUnit.Case, async: true

  alias AgentSea.Embeddings
  alias AgentSea.Embedder.Hashing
  alias AgentSea.VectorStore.Pinecone

  # A Req adapter faking the Pinecone data plane, routing on path. An Agent holds
  # the upserted vectors so query/delete/count behave.
  defp fake_index do
    {:ok, vectors} = Agent.start_link(fn -> %{} end)

    adapter = fn request ->
      {request, Req.Response.new(status: 200, body: route(request, vectors))}
    end

    Pinecone.store(host: "https://idx.svc.pinecone.io", api_key: "k", adapter: adapter)
  end

  defp route(request, vectors) do
    path = request.url.path
    body = decode(request.body)

    cond do
      String.ends_with?(path, "/vectors/upsert") ->
        Enum.each(body["vectors"], fn v -> Agent.update(vectors, &Map.put(&1, v["id"], v)) end)
        %{"upsertedCount" => length(body["vectors"])}

      String.ends_with?(path, "/query") ->
        %{"matches" => matches(vectors, body["topK"])}

      String.ends_with?(path, "/vectors/delete") ->
        Enum.each(body["ids"], fn id -> Agent.update(vectors, &Map.delete(&1, id)) end)
        %{}

      String.ends_with?(path, "/describe_index_stats") ->
        %{"totalVectorCount" => map_size(Agent.get(vectors, & &1))}
    end
  end

  defp matches(vectors, top_k) do
    vectors
    |> Agent.get(& &1)
    |> Map.values()
    |> Enum.take(top_k)
    |> Enum.map(fn v -> %{"id" => v["id"], "score" => 0.8, "metadata" => v["metadata"]} end)
  end

  defp decode(body) when is_map(body), do: body
  defp decode(body), do: body |> IO.iodata_to_binary() |> Jason.decode!()

  test "store/2 requires a host" do
    assert Pinecone.store(host: "h").host == "h"
    assert_raise KeyError, fn -> Pinecone.store(api_key: "k") end
  end

  test "upsert, count and delete round-trip" do
    store = fake_index()
    {:ok, [v1, v2]} = Hashing.embed(["a", "b"])

    assert :ok = Pinecone.upsert(store, [%{id: "1", vector: v1}, %{id: "2", vector: v2}])
    assert Pinecone.count(store) == 2

    assert :ok = Pinecone.delete(store, ["1"])
    assert Pinecone.count(store) == 1
  end

  test "query splits text out of metadata into a hit" do
    store = fake_index()
    {:ok, [v]} = Hashing.embed(["hi"])

    Pinecone.upsert(store, [
      %{id: "7", vector: v, text: "hello world", metadata: %{"lang" => "en"}}
    ])

    assert [hit] = Pinecone.query(store, v, 5, [])
    assert hit.id == "7"
    assert hit.score == 0.8
    assert hit.text == "hello world"
    assert hit.metadata == %{"lang" => "en"}
  end

  test "works through the Embeddings facade" do
    store = fake_index()
    handle = Embeddings.new(store_mod: Pinecone, store: store, embedder: Hashing)

    Embeddings.index(handle, [%{id: "a", text: "refund policy"}, %{id: "b", text: "hours"}])
    assert [_ | _] = Embeddings.search(handle, "refund", 2)
  end

  test "raises on a non-2xx response" do
    adapter = fn request ->
      {request, Req.Response.new(status: 403, body: %{"message" => "no"})}
    end

    store = Pinecone.store(host: "h", adapter: adapter)

    assert_raise RuntimeError, ~r/Pinecone/, fn -> Pinecone.count(store) end
  end
end
