defmodule AgentSea.MCP.Transport.Http do
  @moduledoc """
  MCP "Streamable HTTP" transport. Each request is a JSON-RPC POST to the server
  endpoint; the response is parsed from either an `application/json` body or a
  `text/event-stream` (SSE) body.

  A `GenServer` so it can carry the `Mcp-Session-Id` the server hands back on
  `initialize` and replay it on subsequent requests.

      {:ok, transport} = AgentSea.MCP.Transport.Http.start_link(url: "https://host/mcp")
      {:ok, client} = AgentSea.MCP.connect({AgentSea.MCP.Transport.Http, transport})
  """

  use GenServer

  @behaviour AgentSea.MCP.Transport

  @request_timeout 30_000

  # --- Transport callback ---

  @impl AgentSea.MCP.Transport
  def request(server, method, params) do
    GenServer.call(server, {:request, method, params}, @request_timeout)
  end

  # --- Client API ---

  @doc "Start the transport. Options: `:url` (required), `:headers`, `:adapter`, `:name`."
  def start_link(opts) do
    {gen_opts, init_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  # --- Server ---

  @impl true
  def init(opts) do
    state = %{
      url: Keyword.fetch!(opts, :url),
      headers: Keyword.get(opts, :headers, []),
      adapter: opts[:adapter],
      session_id: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:request, method, params}, _from, state) do
    payload = %{
      "jsonrpc" => "2.0",
      "id" => System.unique_integer([:positive]),
      "method" => method,
      "params" => params
    }

    case Req.post(req(state), url: state.url, json: payload) do
      {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
        {:reply, decode(response), capture_session(state, response)}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:reply, {:error, {:http_error, status, body}}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # --- Request building ---

  defp req(state) do
    headers =
      state.headers ++
        session_header(state.session_id) ++
        [{"accept", "application/json, text/event-stream"}]

    [headers: headers]
    |> maybe_put(:adapter, state.adapter)
    |> Req.new()
  end

  defp session_header(nil), do: []
  defp session_header(id), do: [{"mcp-session-id", id}]

  defp maybe_put(kw, _key, nil), do: kw
  defp maybe_put(kw, key, value), do: Keyword.put(kw, key, value)

  defp capture_session(state, response) do
    case Req.Response.get_header(response, "mcp-session-id") do
      [id | _] -> %{state | session_id: id}
      _ -> state
    end
  end

  # --- Response decoding ---

  # Req auto-decodes application/json into a map.
  defp decode(%Req.Response{body: %{"result" => result}}), do: {:ok, result}
  defp decode(%Req.Response{body: %{"error" => error}}), do: {:error, {:rpc_error, error}}

  # A raw body may be JSON or an SSE stream carrying the JSON-RPC message.
  defp decode(%Req.Response{body: body}) when is_binary(body) do
    case extract_message(body) do
      {:ok, %{"result" => result}} -> {:ok, result}
      {:ok, %{"error" => error}} -> {:error, {:rpc_error, error}}
      _ -> {:error, :invalid_response}
    end
  end

  defp decode(_response), do: {:error, :invalid_response}

  defp extract_message(body) do
    case Jason.decode(body) do
      {:ok, %{} = message} ->
        {:ok, message}

      _ ->
        # SSE: take the last `data:` line and decode it.
        body
        |> String.split("\n")
        |> Enum.filter(&String.starts_with?(&1, "data:"))
        |> Enum.map(&(&1 |> String.replace_prefix("data:", "") |> String.trim()))
        |> List.last()
        |> case do
          nil -> :error
          data -> Jason.decode(data)
        end
    end
  end
end
