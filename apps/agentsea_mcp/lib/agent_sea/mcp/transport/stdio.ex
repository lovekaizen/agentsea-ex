defmodule AgentSea.MCP.Transport.Stdio do
  @moduledoc """
  MCP stdio transport: spawns an MCP server subprocess and speaks newline-
  delimited JSON-RPC 2.0 over its stdin/stdout.

  It's a `GenServer` that owns the `Port`, assigns request ids, buffers incoming
  bytes into lines, and replies to each caller when the matching response id
  arrives. The client's `ref` is this process.

      {:ok, transport} =
        AgentSea.MCP.Transport.Stdio.start_link(command: ["node", "my-mcp-server.js"])

      {:ok, client} = AgentSea.MCP.connect({AgentSea.MCP.Transport.Stdio, transport})
  """

  use GenServer

  @behaviour AgentSea.MCP.Transport

  @request_timeout 15_000

  # --- Transport callback ---

  @impl AgentSea.MCP.Transport
  def request(server, method, params) do
    GenServer.call(server, {:request, method, params}, @request_timeout)
  end

  # --- Client API ---

  @doc "Start the transport. Options: `:command` (`[executable | args]`), `:name`."
  def start_link(opts) do
    {gen_opts, init_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  # --- Server ---

  @impl GenServer
  def init(opts) do
    [executable | args] = Keyword.fetch!(opts, :command)

    path =
      System.find_executable(executable) ||
        raise ArgumentError, "executable not found on PATH: #{executable}"

    port =
      Port.open(
        {:spawn_executable, path},
        [:binary, :exit_status, :use_stdio, :hide, args: args]
      )

    {:ok, %{port: port, buffer: "", next_id: 1, pending: %{}}}
  end

  @impl GenServer
  def handle_call({:request, method, params}, from, state) do
    id = state.next_id

    payload =
      Jason.encode!(%{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params})

    Port.command(state.port, payload <> "\n")

    {:noreply, %{state | next_id: id + 1, pending: Map.put(state.pending, id, from)}}
  end

  @impl GenServer
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    {lines, buffer} = take_lines(state.buffer <> data)
    state = Enum.reduce(lines, %{state | buffer: buffer}, &handle_line/2)
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    # Fail any in-flight requests so callers don't hang.
    for {_id, from} <- state.pending, do: GenServer.reply(from, {:error, {:server_exited, status}})
    {:stop, :normal, %{state | pending: %{}}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # --- Helpers ---

  defp handle_line(line, state) do
    case Jason.decode(line) do
      {:ok, %{"id" => id} = message} ->
        case Map.pop(state.pending, id) do
          {nil, _pending} -> state
          {from, pending} -> reply_and_remove(state, from, message, pending)
        end

      # Notifications (no id) and non-JSON lines are ignored.
      _ ->
        state
    end
  end

  defp reply_and_remove(state, from, message, pending) do
    GenServer.reply(from, rpc_reply(message))
    %{state | pending: pending}
  end

  defp rpc_reply(%{"result" => result}), do: {:ok, result}
  defp rpc_reply(%{"error" => error}), do: {:error, {:rpc_error, error}}
  defp rpc_reply(_message), do: {:error, :invalid_response}

  # Split a buffer into complete lines + trailing remainder.
  defp take_lines(buffer) do
    parts = String.split(buffer, "\n")
    {lines, [rest]} = Enum.split(parts, length(parts) - 1)
    {Enum.reject(lines, &(&1 == "")), rest}
  end
end
