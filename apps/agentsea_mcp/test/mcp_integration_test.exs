defmodule AgentSea.MCP.IntegrationTest do
  # async: false — the agent runs in its own process and consumes Mox
  # expectations in global mode.
  use ExUnit.Case, async: false

  import Mox

  alias AgentSea.{Agent, Response, ToolCall}
  alias AgentSea.MCP
  alias AgentSea.MCP.{Client, MockProvider}
  alias AgentSea.MCP.Transport.Function

  setup :set_mox_global
  setup :verify_on_exit!

  defp weather_server do
    fn
      "initialize", _ ->
        {:ok, %{"serverInfo" => %{"name" => "weather"}}}

      "tools/list", _ ->
        {:ok,
         %{
           "tools" => [
             %{"name" => "get_weather", "description" => "Current weather", "inputSchema" => %{}}
           ]
         }}

      "tools/call", %{"name" => "get_weather", "arguments" => %{"city" => city}} ->
        {:ok, %{"content" => [%{"type" => "text", "text" => "It is sunny in #{city}."}]}}
    end
  end

  test "an agent discovers and calls an MCP tool, then answers from the result" do
    client =
      start_supervised!(%{
        id: :mcp,
        start: {Client, :start_link, [[transport: {Function, weather_server()}]]}
      })

    tools = MCP.to_tool_specs(client)

    MockProvider
    |> expect(:complete, fn _messages, opts ->
      # The MCP tool should be advertised to the provider.
      assert Enum.any?(opts[:tools] || [], &(&1.name == "get_weather"))

      {:ok,
       %Response{
         stop_reason: :tool_use,
         tool_calls: [
           %ToolCall{id: "t1", name: "get_weather", arguments: %{"city" => "Oslo"}}
         ]
       }}
    end)
    |> expect(:complete, fn messages, _opts ->
      tool_message = Enum.find(messages, &(&1.role == :tool))
      assert tool_message.content =~ "It is sunny in Oslo."
      {:ok, %Response{content: "The weather in Oslo is sunny."}}
    end)

    config = %Agent.Config{
      name: :mcp_agent,
      model: "m",
      provider: {MockProvider, []},
      tools: tools
    }

    agent = start_supervised!({Agent, config})

    assert {:ok, %Response{content: "The weather in Oslo is sunny."}} =
             Agent.run(agent, "what's the weather in Oslo?")
  end
end
