defmodule AgentSea.Web.ChatController do
  @moduledoc """
  OpenAI-compatible `POST /v1/chat/completions`, served through `AgentSea.Gateway`.

  Any OpenAI client can point its base URL at this endpoint. Requests are routed
  across the gateway's configured providers (strategy + failover + circuit
  breaking); responses are mapped back to the OpenAI shape. With `stream: true`
  the gateway's streaming path is used and each provider event is forwarded as an
  OpenAI Server-Sent-Event chunk — real token streaming, not a post-hoc split.

  The gateway server is resolved from `config :agentsea_web, :gateway` (default
  `AgentSea.Web.Gateway`).
  """

  use Phoenix.Controller, formats: [:json]
  import Plug.Conn

  def create(conn, params) do
    messages = decode_messages(params["messages"] || [])
    model = params["model"] || "agentsea"

    if params["stream"] == true do
      case AgentSea.Gateway.stream(gateway(), messages) do
        {:ok, stream, _served_by} -> stream_sse(conn, model, stream)
        {:error, reason} -> gateway_error(conn, reason)
      end
    else
      case AgentSea.Gateway.completion(gateway(), messages) do
        {:ok, response, _served_by} -> json(conn, completion_body(model, response))
        {:error, reason} -> gateway_error(conn, reason)
      end
    end
  end

  defp gateway, do: Application.get_env(:agentsea_web, :gateway, AgentSea.Web.Gateway)

  defp gateway_error(conn, reason) do
    conn
    |> put_status(502)
    |> json(%{
      error: %{
        message: "No provider available to handle the request.",
        type: "gateway_error",
        code: to_string(reason)
      }
    })
  end

  # --- Request decoding ---

  defp decode_messages(messages) do
    Enum.map(messages, fn m ->
      %{role: role_atom(m["role"]), content: m["content"] || ""}
    end)
  end

  defp role_atom("system"), do: :system
  defp role_atom("assistant"), do: :assistant
  defp role_atom("tool"), do: :tool
  defp role_atom(_), do: :user

  # --- Non-streaming response ---

  defp completion_body(model, response) do
    %{
      id: new_id(),
      object: "chat.completion",
      created: System.system_time(:second),
      model: model,
      choices: [
        %{
          index: 0,
          message: %{role: "assistant", content: response.content},
          finish_reason: finish_reason(response.stop_reason)
        }
      ],
      usage: usage(response)
    }
  end

  # --- Streaming (SSE) response: forward each provider event as a chunk ---

  defp stream_sse(conn, model, stream) do
    id = new_id()
    created = System.system_time(:second)

    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> send_chunked(200)

    conn
    |> send_event(chunk_body(id, created, model, %{role: "assistant"}, nil))
    |> forward_stream(stream, id, created, model)
    |> send_event(chunk_body(id, created, model, %{}, "stop"))
    |> send_done()
  end

  defp forward_stream(conn, stream, id, created, model) do
    Enum.reduce(stream, conn, fn
      {:content, delta}, c ->
        send_event(c, chunk_body(id, created, model, %{content: delta}, nil))

      # :done, thinking, tool_call, … aren't surfaced as OpenAI content deltas
      _event, c ->
        c
    end)
  end

  defp send_event(conn, body) do
    {:ok, conn} = chunk(conn, "data: #{Jason.encode!(body)}\n\n")
    conn
  end

  defp send_done(conn) do
    {:ok, conn} = chunk(conn, "data: [DONE]\n\n")
    conn
  end

  defp chunk_body(id, created, model, delta, finish_reason) do
    %{
      id: id,
      object: "chat.completion.chunk",
      created: created,
      model: model,
      choices: [%{index: 0, delta: delta, finish_reason: finish_reason}]
    }
  end

  # --- Shared mapping ---

  defp usage(response) do
    input = response.usage.input_tokens
    output = response.usage.output_tokens
    %{prompt_tokens: input, completion_tokens: output, total_tokens: input + output}
  end

  defp finish_reason(:stop), do: "stop"
  defp finish_reason(:length), do: "length"
  defp finish_reason(:tool_use), do: "tool_calls"
  defp finish_reason(_), do: "stop"

  defp new_id, do: "chatcmpl-" <> Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)
end
