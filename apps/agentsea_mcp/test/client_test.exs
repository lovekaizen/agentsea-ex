defmodule AgentSea.MCP.ClientTest do
  use ExUnit.Case, async: true

  alias AgentSea.MCP
  alias AgentSea.MCP.Client
  alias AgentSea.MCP.Transport.Function

  # A minimal in-memory MCP "server" as a transport function.
  defp server do
    fn
      "initialize", _params ->
        {:ok, %{"protocolVersion" => "2024-11-05", "serverInfo" => %{"name" => "demo", "version" => "1.0"}}}

      "tools/list", _params ->
        {:ok,
         %{
           "tools" => [
             %{"name" => "echo", "description" => "Echo text", "inputSchema" => %{"type" => "object"}},
             %{"name" => "boom", "description" => "Always errors", "inputSchema" => %{}}
           ]
         }}

      "tools/call", %{"name" => "echo", "arguments" => args} ->
        {:ok, %{"content" => [%{"type" => "text", "text" => "echo: #{args["text"]}"}]}}

      "tools/call", %{"name" => "boom"} ->
        {:ok, %{"isError" => true, "content" => [%{"type" => "text", "text" => "kaboom"}]}}
    end
  end

  defp start_client do
    start_supervised!(%{
      id: :mcp,
      start: {Client, :start_link, [[transport: {Function, server()}]]}
    })
  end

  test "handshake caches server info and tools" do
    client = start_client()
    assert Client.server_info(client) == %{"name" => "demo", "version" => "1.0"}
    assert Enum.map(Client.list_tools(client), & &1["name"]) == ["echo", "boom"]
  end

  test "calls a tool and returns its text" do
    client = start_client()
    assert {:ok, "echo: hi"} = Client.call_tool(client, "echo", %{"text" => "hi"})
  end

  test "surfaces an isError tool result" do
    client = start_client()
    assert {:error, {:tool_error, "kaboom"}} = Client.call_tool(client, "boom", %{})
  end

  test "to_tool_specs builds runnable AgentSea.Tool.Spec values" do
    client = start_client()
    specs = MCP.to_tool_specs(client)

    assert Enum.map(specs, & &1.name) == ["echo", "boom"]
    echo = Enum.find(specs, &(&1.name == "echo"))
    assert %AgentSea.Tool.Spec{} = echo
    assert {:ok, "echo: world"} = echo.run.(%{"text" => "world"}, %{})
  end
end
