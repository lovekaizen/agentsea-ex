defmodule AgentSea.Web.ChatController do
  @moduledoc """
  OpenAI-compatible `POST /v1/chat/completions`, served through `AgentSea.Gateway`.

  Any OpenAI client can point its base URL at this endpoint. Requests are routed
  across the gateway's configured providers (strategy + failover + circuit
  breaking); responses are mapped back to the OpenAI shape. With `stream: true`
  the response is delivered as Server-Sent Events.

  The gateway server is resolved from `config :agentsea_web, :gateway` (default
  `AgentSea.Web.Gateway`) — start/register a gateway under that name.
  """

  use Phoenix.Controller, formats: [:json]
  import Plug.Conn

  def create(conn, params) do
    messages = decode_messages(params["messages"] || [])
    model = params["model"] || "agentsea"
    stream? = params["stream"] == true

    case AgentSea.Gateway.completion(gateway(), messages) do
      {:ok, response, _served_by} ->
        if stream?,
          do: stream_completion(conn, model, response),
          else: json(conn, completion_body(model, response))

      {:error, reason} ->
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
  end

  defp gateway, do: Application.get_env(:agentsea_web, :gateway, AgentSea.Web.Gateway)

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

  # --- Streaming (SSE) response ---

  defp stream_completion(conn, model, response) do
    id = new_id()
    created = System.system_time(:second)

    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> send_chunked(200)

    conn
    # role delta
    |> send_event(chunk_body(id, created, model, %{role: "assistant"}, nil))
    # content deltas (the gateway fronts non-streaming providers, so we split the
    # completed text into word-sized deltas)
    |> stream_content(response.content, fn delta, c ->
      send_event(c, chunk_body(id, created, model, %{content: delta}, nil))
    end)
    # final delta + sentinel
    |> send_event(chunk_body(id, created, model, %{}, finish_reason(response.stop_reason)))
    |> send_done()
  end

  defp stream_content(conn, "", _fun), do: conn

  defp stream_content(conn, content, fun) do
    content
    |> word_deltas()
    |> Enum.reduce(conn, fn delta, c -> fun.(delta, c) end)
  end

  defp word_deltas(content) do
    content
    |> String.split(" ")
    |> Enum.with_index()
    |> Enum.map(fn {word, 0} -> word
      {word, _} -> " " <> word
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
