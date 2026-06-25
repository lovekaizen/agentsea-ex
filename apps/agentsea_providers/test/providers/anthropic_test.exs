defmodule AgentSea.Providers.AnthropicTest do
  use ExUnit.Case, async: true

  alias AgentSea.Providers.Anthropic
  alias AgentSea.{Response, ToolCall}

  # Build a Req adapter that returns a fixed JSON response, optionally running
  # `assert_fn` against the decoded request body first.
  defp adapter(resp_map, status \\ 200, assert_fn \\ nil) do
    fn request ->
      if assert_fn, do: assert_fn.(decode_body(request.body))
      response = Req.Response.new(status: status, body: resp_map)
      {request, response}
    end
  end

  defp decode_body(nil), do: %{}
  defp decode_body(body) when is_map(body), do: body
  # Req encodes a `json:` body to iodata before the adapter runs.
  defp decode_body(body), do: body |> IO.iodata_to_binary() |> Jason.decode!()

  defp opts(adapter), do: [model: "claude-haiku-4-5", api_key: "test", adapter: adapter]

  test "normalizes a text completion" do
    a =
      adapter(%{
        "content" => [%{"type" => "text", "text" => "Hello!"}],
        "stop_reason" => "end_turn",
        "usage" => %{"input_tokens" => 5, "output_tokens" => 2}
      })

    assert {:ok, %Response{} = resp} =
             Anthropic.complete([%{role: :user, content: "hi"}], opts(a))

    assert resp.content == "Hello!"
    assert resp.stop_reason == :stop
    assert resp.tool_calls == []
    assert resp.usage == %{input_tokens: 5, output_tokens: 2}
  end

  test "normalizes a tool_use response into ToolCalls" do
    a =
      adapter(%{
        "content" => [
          %{"type" => "text", "text" => "Let me check."},
          %{
            "type" => "tool_use",
            "id" => "toolu_1",
            "name" => "get_weather",
            "input" => %{"city" => "Oslo"}
          }
        ],
        "stop_reason" => "tool_use",
        "usage" => %{"input_tokens" => 10, "output_tokens" => 7}
      })

    assert {:ok, %Response{stop_reason: :tool_use, tool_calls: [call]}} =
             Anthropic.complete([%{role: :user, content: "weather?"}], opts(a))

    assert %ToolCall{id: "toolu_1", name: "get_weather", arguments: %{"city" => "Oslo"}} = call
  end

  test "sends model + system prompt and converts tool result messages" do
    assert_body = fn body ->
      assert body["model"] == "claude-haiku-4-5"
      assert body["system"] == "be terse"

      tool_result_turns =
        Enum.filter(body["messages"], &match?(%{"content" => [%{"type" => "tool_result"}]}, &1))

      assert [%{"content" => [tr]}] = tool_result_turns
      assert tr["tool_use_id"] == "t1"
      assert tr["content"] == "echo: hi"
    end

    a =
      adapter(
        %{
          "content" => [%{"type" => "text", "text" => "ok"}],
          "stop_reason" => "end_turn",
          "usage" => %{"input_tokens" => 1, "output_tokens" => 1}
        },
        200,
        assert_body
      )

    messages = [
      %{role: :user, content: "hi"},
      %{role: :tool, tool_call_id: "t1", name: "echo", content: "echo: hi"}
    ]

    assert {:ok, %Response{content: "ok"}} =
             Anthropic.complete(messages, opts(a) ++ [system_prompt: "be terse"])
  end

  test "surfaces non-200 responses as errors" do
    a = adapter(%{"error" => %{"type" => "rate_limit"}}, 429)

    assert {:error, {:http_error, 429, _}} =
             Anthropic.complete([%{role: :user, content: "hi"}], opts(a))
  end

  test "model_info reports capabilities for known models and nil otherwise" do
    assert %AgentSea.ModelInfo{thinking: true, tools: true} =
             Anthropic.model_info("claude-opus-4-8")

    assert Anthropic.model_info("unknown-model") == nil
  end
end
