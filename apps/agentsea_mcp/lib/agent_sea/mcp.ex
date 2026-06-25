defmodule AgentSea.MCP do
  @moduledoc """
  Model Context Protocol integration: connect to an MCP server and expose its
  tools to an AgentSea agent.

  ## Example

      # `transport` is any (method, params) -> {:ok, result} | {:error, reason}
      {:ok, client} =
        AgentSea.MCP.connect({AgentSea.MCP.Transport.Function, transport})

      tools = AgentSea.MCP.to_tool_specs(client)
      # add `tools` to an AgentSea.Agent's config — the model can now call them
  """

  alias AgentSea.MCP.Client

  @doc "Start an MCP client for a `{transport_module, ref}`."
  @spec connect({module(), term()}, keyword()) :: GenServer.on_start()
  def connect(transport, opts \\ []) do
    Client.start_link([transport: transport] ++ opts)
  end

  @doc """
  Connect to an MCP server subprocess over stdio. `command` is `[executable |
  args]` (e.g. `["node", "server.js"]`). Returns `{:ok, client}`.
  """
  @spec connect_stdio([String.t()], keyword()) :: GenServer.on_start()
  def connect_stdio(command, opts \\ []) do
    with {:ok, transport} <- AgentSea.MCP.Transport.Stdio.start_link(command: command) do
      connect({AgentSea.MCP.Transport.Stdio, transport}, opts)
    end
  end

  @doc """
  Connect to an MCP server over Streamable HTTP. `url` is the server endpoint;
  `:headers` and `:adapter` are forwarded to the transport. Returns `{:ok, client}`.
  """
  @spec connect_http(String.t(), keyword()) :: GenServer.on_start()
  def connect_http(url, opts \\ []) do
    transport_opts = [url: url] ++ Keyword.take(opts, [:headers, :adapter])

    with {:ok, transport} <- AgentSea.MCP.Transport.Http.start_link(transport_opts) do
      connect({AgentSea.MCP.Transport.Http, transport}, Keyword.drop(opts, [:headers, :adapter]))
    end
  end

  @doc """
  Adapt the server's tools into `AgentSea.Tool.Spec` values an agent can use.
  Each spec's `run` calls the tool through the client.
  """
  @spec to_tool_specs(GenServer.server()) :: [AgentSea.Tool.Spec.t()]
  def to_tool_specs(client) do
    client
    |> Client.list_tools()
    |> Enum.map(fn tool ->
      name = tool["name"]

      %AgentSea.Tool.Spec{
        name: name,
        description: tool["description"],
        schema: input_schema(tool["inputSchema"]),
        run: fn args, _ctx -> Client.call_tool(client, name, args) end
      }
    end)
  end

  # MCP advertises a JSON-schema input shape; keep it as opaque metadata for now.
  defp input_schema(nil), do: []
  defp input_schema(schema), do: [json_schema: schema]
end
