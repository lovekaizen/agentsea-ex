defmodule AgentSea.VectorStore.QdrantTest do
  use ExUnit.Case, async: true

  alias AgentSea.Embeddings
  alias AgentSea.Embedder.Hashing
  alias AgentSea.VectorStore.Qdrant

  # A Req adapter that fakes a Qdrant server, routing on method + path. `state`
  # is an Agent holding the upserted points so search/count behave.
  defp fake_server do
    {:ok, points} = Agent.start_link(fn -> %{} end)

    adapter = fn request ->
      {request, Req.Response.new(status: 200, body: route(request, points))}
    end

    Qdrant.store(collection: "docs", adapter: adapter)
  end

  defp route(request, points) do
    path = request.url.path
    body = decode(request.body)

    cond do
      request.method == :put and String.ends_with?(path, "/points") ->
        Enum.each(body["points"], fn p -> Agent.update(points, &Map.put(&1, p["id"], p)) end)
        ok(%{"status" => "acknowledged"})

      request.method == :put ->
        ok(true)

      String.ends_with?(path, "/points/search") ->
        ok(search(points, body["limit"]))

      String.ends_with?(path, "/points/count") ->
        ok(%{"count" => map_size(Agent.get(points, & &1))})

      String.ends_with?(path, "/points/delete") ->
        Enum.each(body["points"], fn id -> Agent.update(points, &Map.delete(&1, id)) end)
        ok(%{"status" => "acknowledged"})
    end
  end

  defp search(points, limit) do
    points
    |> Agent.get(& &1)
    |> Map.values()
    |> Enum.take(limit)
    |> Enum.map(fn p -> %{"id" => p["id"], "score" => 0.9, "payload" => p["payload"]} end)
  end

  defp ok(result), do: %{"result" => result, "status" => "ok"}

  defp decode(body) when is_map(body), do: body
  defp decode(body), do: body |> IO.iodata_to_binary() |> Jason.decode!()

  test "store/2 requires a collection and defaults the url" do
    store = Qdrant.store(collection: "c")
    assert store.collection == "c"
    assert store.url == "http://localhost:6333"
    assert_raise KeyError, fn -> Qdrant.store(url: "x") end
  end

  test "ensure_collection issues a PUT and returns :ok" do
    store = fake_server()
    assert :ok = Qdrant.ensure_collection(store, 64)
  end

  test "upsert, count and delete round-trip" do
    store = fake_server()
    {:ok, [v1, v2]} = Hashing.embed(["alpha", "beta"])

    assert :ok = Qdrant.upsert(store, [%{id: 1, vector: v1, text: "alpha"}, %{id: 2, vector: v2}])
    assert Qdrant.count(store) == 2

    assert :ok = Qdrant.delete(store, [1])
    assert Qdrant.count(store) == 1
  end

  test "query maps Qdrant results to hits (id, score, text, metadata)" do
    store = fake_server()
    {:ok, [v]} = Hashing.embed(["hello"])

    Qdrant.upsert(store, [%{id: 7, vector: v, text: "hello world", metadata: %{"lang" => "en"}}])

    assert [hit] = Qdrant.query(store, v, 5, [])
    assert hit.id == 7
    assert hit.score == 0.9
    assert hit.text == "hello world"
    assert hit.metadata == %{"lang" => "en"}
  end

  test "works through the Embeddings facade" do
    store = fake_server()
    handle = Embeddings.new(store_mod: Qdrant, store: store, embedder: Hashing)

    Embeddings.index(handle, [%{id: 1, text: "refund policy"}, %{id: 2, text: "opening hours"}])
    assert [_ | _] = Embeddings.search(handle, "refund", 2)
  end

  test "raises on a non-2xx response" do
    adapter = fn request ->
      {request, Req.Response.new(status: 500, body: %{"status" => "error"})}
    end

    store = Qdrant.store(collection: "c", adapter: adapter)

    assert_raise RuntimeError, ~r/Qdrant/, fn -> Qdrant.count(store) end
  end
end
