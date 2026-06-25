defmodule AgentSea.MCP.Transport.HttpTest do
  use ExUnit.Case, async: true

  alias AgentSea.MCP
  alias AgentSea.MCP.Client
  alias AgentSea.MCP.Transport.Http

  # A Req adapter that acts as a Streamable-HTTP MCP server. After `initialize`
  # it hands back an Mcp-Session-Id and asserts every later request replays it.
  defp server(opts \\ []) do
    sse? = Keyword.get(opts, :sse, false)

    fn request ->
      payload = decode_body(request.body)
      method = payload["method"]
      id = payload["id"]

      if method != "initialize" do
        assert Req.Request.get_header(request, "mcp-session-id") == ["sess-123"]
      end

      {result, headers} = handle(method, id)
      body = if sse?, do: "event: message\ndata: #{Jason.encode!(result)}\n\n", else: result

      {request, Req.Response.new(status: 200, body: body, headers: headers)}
    end
  end

  defp handle("initialize", id),
    do:
      {%{"jsonrpc" => "2.0", "id" => id, "result" => %{"serverInfo" => %{"name" => "http"}}},
       [{"mcp-session-id", "sess-123"}]}

  defp handle("tools/list", id),
    do:
      {%{
         "jsonrpc" => "2.0",
         "id" => id,
         "result" => %{"tools" => [%{"name" => "echo", "description" => "Echo", "inputSchema" => %{}}]}
       }, []}

  defp handle("tools/call", id),
    do:
      {%{
         "jsonrpc" => "2.0",
         "id" => id,
         "result" => %{"content" => [%{"type" => "text", "text" => "echo: hi"}]}
       }, []}

  defp start(adapter) do
    transport =
      start_supervised!(%{
        id: :http,
        start: {Http, :start_link, [[url: "https://example/mcp", adapter: adapter]]}
      })

    start_supervised!(%{id: :client, start: {Client, :start_link, [[transport: {Http, transport}]]}})
  end

  test "handshake over HTTP, captures + replays the session id, lists tools" do
    client = start(server())
    assert Client.server_info(client) == %{"name" => "http"}
    assert Enum.map(Client.list_tools(client), & &1["name"]) == ["echo"]
  end

  test "calls a tool over HTTP" do
    client = start(server())
    assert {:ok, "echo: hi"} = Client.call_tool(client, "echo", %{"text" => "hi"})
  end

  test "parses a JSON-RPC message delivered as SSE" do
    client = start(server(sse: true))
    assert {:ok, "echo: hi"} = Client.call_tool(client, "echo", %{"text" => "hi"})
  end

  test "connect_http convenience wires transport + client" do
    assert {:ok, client} = MCP.connect_http("https://example/mcp", adapter: server())
    assert Enum.map(Client.list_tools(client), & &1["name"]) == ["echo"]
  end

  defp decode_body(body) when is_map(body), do: body
  defp decode_body(body), do: body |> IO.iodata_to_binary() |> Jason.decode!()
end
