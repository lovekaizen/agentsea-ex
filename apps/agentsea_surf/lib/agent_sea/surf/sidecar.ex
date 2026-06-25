defmodule AgentSea.Surf.Sidecar do
  @moduledoc """
  Drives a Node browser-automation subprocess over a `Port`.

  A `GenServer` owns the subprocess and speaks newline-delimited JSON: each
  request `{"id":N,"command":...,"args":{...}}` gets a response
  `{"id":N,"ok":true|false,"result"|"error":...}`. Browser/computer-use lives in
  the Node side (Playwright); only the I/O is bridged — the same "bridge, don't
  reimplement" pattern as the MCP stdio transport.
  """

  use GenServer

  @timeout 30_000

  # --- Client API ---

  @doc "Start a sidecar. Options: `:command` (`[executable | args]`), `:name`."
  def start_link(opts) do
    {gen_opts, init_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  @doc "Send a command to the Node side; returns `{:ok, result}` or `{:error, reason}`."
  @spec call(GenServer.server(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def call(server, command, args \\ %{}) do
    GenServer.call(server, {:call, command, args}, @timeout)
  end

  # --- Server ---

  @impl true
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

  @impl true
  def handle_call({:call, command, args}, from, state) do
    id = state.next_id
    payload = Jason.encode!(%{"id" => id, "command" => command, "args" => args})
    Port.command(state.port, payload <> "\n")
    {:noreply, %{state | next_id: id + 1, pending: Map.put(state.pending, id, from)}}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    {lines, buffer} = take_lines(state.buffer <> data)
    state = Enum.reduce(lines, %{state | buffer: buffer}, &handle_line/2)
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    for {_id, from} <- state.pending, do: GenServer.reply(from, {:error, {:sidecar_exited, status}})
    {:stop, :normal, %{state | pending: %{}}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # --- Helpers ---

  defp handle_line(line, state) do
    case Jason.decode(line) do
      {:ok, %{"id" => id} = message} ->
        case Map.pop(state.pending, id) do
          {nil, _pending} -> state
          {from, pending} -> reply(state, from, message, pending)
        end

      _ ->
        state
    end
  end

  defp reply(state, from, message, pending) do
    GenServer.reply(from, response(message))
    %{state | pending: pending}
  end

  defp response(%{"ok" => true, "result" => result}), do: {:ok, result}
  defp response(%{"ok" => false, "error" => error}), do: {:error, error}
  defp response(_message), do: {:error, :invalid_response}

  defp take_lines(buffer) do
    parts = String.split(buffer, "\n")
    {lines, [rest]} = Enum.split(parts, length(parts) - 1)
    {Enum.reject(lines, &(&1 == "")), rest}
  end
end
