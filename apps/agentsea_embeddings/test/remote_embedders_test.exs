defmodule AgentSea.RemoteEmbeddersTest do
  use ExUnit.Case, async: true

  alias AgentSea.Embedder.{OpenAI, Cohere}

  defp adapter(body, status \\ 200, assert_fn \\ nil) do
    fn request ->
      if assert_fn, do: assert_fn.(request)
      {request, Req.Response.new(status: status, body: body)}
    end
  end

  defp decode(body) when is_map(body), do: body
  defp decode(body), do: body |> IO.iodata_to_binary() |> Jason.decode!()

  describe "OpenAI" do
    test "returns vectors in input order (by response index)" do
      # Deliberately out of order to prove we sort by index.
      resp = %{
        "data" => [
          %{"index" => 1, "embedding" => [0.3, 0.4]},
          %{"index" => 0, "embedding" => [0.1, 0.2]}
        ]
      }

      assert {:ok, [[0.1, 0.2], [0.3, 0.4]]} =
               OpenAI.embed(["a", "b"], api_key: "k", adapter: adapter(resp))
    end

    test "sends model + input and bearer auth" do
      assert_request = fn request ->
        body = decode(request.body)
        assert body["model"] == "text-embedding-3-small"
        assert body["input"] == ["hi"]
        assert Req.Request.get_header(request, "authorization") == ["Bearer sk-test"]
      end

      resp = %{"data" => [%{"index" => 0, "embedding" => [1.0]}]}

      assert {:ok, [[1.0]]} =
               OpenAI.embed(["hi"],
                 api_key: "sk-test",
                 adapter: adapter(resp, 200, assert_request)
               )
    end

    test "surfaces a non-200 as an error" do
      a = adapter(%{"error" => %{"message" => "bad"}}, 401)
      assert {:error, {:http_error, 401, _}} = OpenAI.embed(["x"], api_key: "k", adapter: a)
    end

    test "dimensions/0 defaults to 1536 and reads config" do
      assert OpenAI.dimensions() == 1536
      Application.put_env(:agentsea_embeddings, :openai_dimensions, 512)
      assert OpenAI.dimensions() == 512
    after
      Application.delete_env(:agentsea_embeddings, :openai_dimensions)
    end
  end

  describe "Cohere" do
    test "returns the embeddings array" do
      resp = %{"embeddings" => [[0.1, 0.2], [0.3, 0.4]]}

      assert {:ok, [[0.1, 0.2], [0.3, 0.4]]} =
               Cohere.embed(["a", "b"], api_key: "k", adapter: adapter(resp))
    end

    test "sends model, texts and input_type" do
      assert_request = fn request ->
        body = decode(request.body)
        assert body["model"] == "embed-english-v3.0"
        assert body["texts"] == ["q"]
        assert body["input_type"] == "search_query"
      end

      resp = %{"embeddings" => [[1.0]]}

      assert {:ok, [[1.0]]} =
               Cohere.embed(["q"],
                 api_key: "k",
                 input_type: "search_query",
                 adapter: adapter(resp, 200, assert_request)
               )
    end

    test "surfaces a non-200 as an error" do
      a = adapter(%{"message" => "nope"}, 429)
      assert {:error, {:http_error, 429, _}} = Cohere.embed(["x"], api_key: "k", adapter: a)
    end

    test "dimensions/0 defaults to 1024" do
      assert Cohere.dimensions() == 1024
    end
  end
end
