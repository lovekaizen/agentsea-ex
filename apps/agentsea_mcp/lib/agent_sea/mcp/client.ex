defmodule AgentSea.MCP.Client do
  @moduledoc """
  An MCP client: performs the `initialize` handshake over a transport, caches the
  server's tool list, and calls tools. Transport-agnostic (see
  `AgentSea.MCP.Transport`).
  """

  use GenServer

  @protocol_version "2024-11-05"

  # --- Client API ---

  @doc """
  Start a client. Options:
    * `:transport` — `{transport_module, ref}` (required)
    * `:name`      — optional process name
  """
  def start_link(opts) do
    {gen_opts, init_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  @doc "The server's advertised tools (raw MCP tool maps)."
  def list_tools(client), do: GenServer.call(client, :list_tools)

  @doc "Call a tool by name with arguments; returns the textual result."
  def call_tool(client, name, args), do: GenServer.call(client, {:call_tool, name, args})

  @doc "Server info from the handshake (`nil` until initialized)."
  def server_info(client), do: GenServer.call(client, :server_info)

  # --- Server ---

  @impl true
  def init(opts) do
    transport = Keyword.fetch!(opts, :transport)
    {:ok, %{transport: transport, tools: [], server_info: nil}, {:continue, :initialize}}
  end

  @impl true
  def handle_continue(:initialize, state) do
    case request(state, "initialize", initialize_params()) do
      {:ok, result} ->
        tools =
          case request(state, "tools/list", %{}) do
            {:ok, %{"tools" => tools}} when is_list(tools) -> tools
            _ -> []
          end

        {:noreply, %{state | tools: tools, server_info: Map.get(result, "serverInfo")}}

      {:error, _reason} ->
        # Stay up with no tools; a real client might retry or stop.
        {:noreply, state}
    end
  end

  @impl true
  def handle_call(:list_tools, _from, state), do: {:reply, state.tools, state}

  def handle_call(:server_info, _from, state), do: {:reply, state.server_info, state}

  def handle_call({:call_tool, name, args}, _from, state) do
    case request(state, "tools/call", %{"name" => name, "arguments" => args}) do
      {:ok, result} ->
        if Map.get(result, "isError", false) do
          {:reply, {:error, {:tool_error, result_text(result)}}, state}
        else
          {:reply, {:ok, result_text(result)}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # --- Helpers ---

  defp request(%{transport: {module, ref}}, method, params),
    do: module.request(ref, method, params)

  defp initialize_params do
    %{
      "protocolVersion" => @protocol_version,
      "capabilities" => %{},
      "clientInfo" => %{"name" => "agentsea", "version" => "0.1.0"}
    }
  end

  defp result_text(%{"content" => content}) when is_list(content) do
    content
    |> Enum.filter(&(&1["type"] == "text"))
    |> Enum.map_join("\n", & &1["text"])
  end

  defp result_text(other), do: inspect(other)
end
