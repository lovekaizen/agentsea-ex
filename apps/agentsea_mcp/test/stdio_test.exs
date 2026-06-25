defmodule AgentSea.MCP.Transport.StdioTest do
  use ExUnit.Case, async: false

  alias AgentSea.MCP.Client
  alias AgentSea.MCP.Transport.Stdio

  @awk_server Path.expand("support/mcp_echo.awk", __DIR__)

  setup do
    # Run a real subprocess (awk) that speaks newline-delimited JSON-RPC.
    unless System.find_executable("awk"), do: raise("awk is required for this test")

    transport =
      start_supervised!(%{
        id: :stdio_transport,
        start: {Stdio, :start_link, [[command: ["awk", "-f", @awk_server]]]}
      })

    client =
      start_supervised!(%{
        id: :mcp_client,
        start: {Client, :start_link, [[transport: {Stdio, transport}]]}
      })

    {:ok, client: client}
  end

  test "performs the handshake over a real stdio subprocess", %{client: client} do
    assert Client.server_info(client) == %{"name" => "echo"}
    assert Enum.map(Client.list_tools(client), & &1["name"]) == ["echo"]
  end

  test "calls a tool over stdio (request/response correlated by id)", %{client: client} do
    assert {:ok, "echo: hello stdio"} =
             Client.call_tool(client, "echo", %{"text" => "hello stdio"})

    # A second call uses a fresh id and still correlates correctly.
    assert {:ok, "echo: again"} = Client.call_tool(client, "echo", %{"text" => "again"})
  end
end
