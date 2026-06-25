defmodule AgentSea.Providers.Anthropic do
  @moduledoc """
  Anthropic Messages API provider. HTTP via `Req`; normalizes responses into
  `AgentSea.Response`.

  Options (passed through the agent's `provider: {__MODULE__, opts}`):

    * `:api_key`   — defaults to `ANTHROPIC_API_KEY`
    * `:base_url`  — defaults to `https://api.anthropic.com`
    * `:max_tokens`— defaults to 1024 (Anthropic requires it)
    * `:adapter`   — a `Req` adapter, used in tests to stub HTTP
  """

  @behaviour AgentSea.Provider

  alias AgentSea.{Response, ToolCall}

  @default_base "https://api.anthropic.com"
  @api_version "2023-06-01"
  @default_max_tokens 1024

  @impl AgentSea.Provider
  def complete(messages, opts) do
    body = build_body(messages, opts)

    case Req.post(req(opts), url: "/v1/messages", json: body) do
      {:ok, %Req.Response{status: 200, body: resp}} ->
        {:ok, normalize(resp)}

      {:ok, %Req.Response{status: status, body: resp}} ->
        {:error, {:http_error, status, resp}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl AgentSea.Provider
  def stream(messages, opts) do
    # Tests (and custom transports) can inject the raw byte stream via
    # `:body_stream`, bypassing Req entirely.
    chunks = opts[:body_stream] || request_stream(messages, opts)

    chunks
    |> AgentSea.Providers.SSE.events()
    |> Stream.flat_map(&to_stream_event/1)
  end

  @impl AgentSea.Provider
  def model_info("claude-opus-4-8") do
    %AgentSea.ModelInfo{
      context_window: 1_000_000,
      max_output_tokens: 64_000,
      tools: true,
      vision: true,
      thinking: true,
      effort: [:low, :medium, :high, :xhigh, :max]
    }
  end

  def model_info("claude-haiku-4-5") do
    %AgentSea.ModelInfo{
      context_window: 200_000,
      max_output_tokens: 32_000,
      tools: true,
      vision: true,
      thinking: false,
      effort: []
    }
  end

  def model_info(_other), do: nil

  # --- Request building ---

  defp req(opts) do
    api_key = opts[:api_key] || System.get_env("ANTHROPIC_API_KEY")

    base = [
      base_url: opts[:base_url] || @default_base,
      headers: [
        {"x-api-key", api_key || ""},
        {"anthropic-version", @api_version}
      ]
    ]

    # `:adapter` (and `:plug`) are only set when provided — used by tests to
    # stub HTTP without hitting the network.
    base
    |> maybe_kw(:adapter, opts[:adapter])
    |> maybe_kw(:plug, opts[:plug])
    |> Req.new()
  end

  defp maybe_kw(kw, _key, nil), do: kw
  defp maybe_kw(kw, key, value), do: Keyword.put(kw, key, value)

  # Open a streaming request and return Req's async body (an enumerable of raw
  # SSE byte chunks). Only used for real network calls; tests inject chunks.
  defp request_stream(messages, opts) do
    body = messages |> build_body(opts) |> Map.put(:stream, true)
    response = Req.post!(req(opts), url: "/v1/messages", json: body, into: :self)
    response.body
  end

  # Map an Anthropic SSE event to AgentSea's normalized stream events.
  defp to_stream_event(%{event: "content_block_delta", data: data}) do
    case Jason.decode(data) do
      {:ok, %{"delta" => %{"type" => "text_delta", "text" => text}}} ->
        [{:content, text}]

      {:ok, %{"delta" => %{"type" => "thinking_delta", "thinking" => text}}} ->
        [{:thinking, text}]

      _ ->
        []
    end
  end

  defp to_stream_event(%{event: "message_stop"}), do: [:done]
  defp to_stream_event(%{event: nil, data: "[DONE]"}), do: [:done]
  defp to_stream_event(_event), do: []

  defp build_body(messages, opts) do
    {system, turns} = split_system(messages)

    %{
      model: Keyword.fetch!(opts, :model),
      max_tokens: opts[:max_tokens] || @default_max_tokens,
      messages: Enum.map(turns, &to_anthropic_message/1)
    }
    |> maybe_put(:system, opts[:system_prompt] || system)
    |> maybe_put(:temperature, opts[:temperature])
    |> maybe_put(:tools, to_anthropic_tools(opts[:tools]))
  end

  defp split_system(messages) do
    {systems, rest} = Enum.split_with(messages, &(&1.role == :system))
    system = Enum.map_join(systems, "\n\n", & &1.content)
    {if(system == "", do: nil, else: system), rest}
  end

  # Tool result messages become a user turn carrying a tool_result block.
  defp to_anthropic_message(%{role: :tool} = msg) do
    %{
      "role" => "user",
      "content" => [
        %{
          "type" => "tool_result",
          "tool_use_id" => msg[:tool_call_id],
          "content" => msg.content
        }
      ]
    }
  end

  defp to_anthropic_message(%{role: role, content: content}) do
    %{"role" => to_string(role), "content" => content}
  end

  defp to_anthropic_tools(nil), do: nil

  defp to_anthropic_tools(tools) do
    Enum.map(tools, fn tool ->
      %{
        "name" => tool.name,
        "description" => tool.description,
        "input_schema" => json_schema(tool.schema)
      }
    end)
  end

  # Minimal NimbleOptions-keyword → JSON-schema object conversion.
  defp json_schema(schema) when is_list(schema) do
    properties =
      for {key, spec} <- schema, into: %{} do
        {to_string(key), %{"type" => json_type(spec[:type])}}
      end

    required =
      for {key, spec} <- schema, spec[:required], do: to_string(key)

    %{"type" => "object", "properties" => properties, "required" => required}
  end

  defp json_schema(_), do: %{"type" => "object", "properties" => %{}}

  defp json_type(:string), do: "string"
  defp json_type(:integer), do: "integer"
  defp json_type(:float), do: "number"
  defp json_type(:boolean), do: "boolean"
  defp json_type(_), do: "string"

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # --- Response normalization ---

  defp normalize(%{"content" => blocks} = resp) do
    text =
      blocks
      |> Enum.filter(&(&1["type"] == "text"))
      |> Enum.map_join("\n", & &1["text"])

    tool_calls =
      blocks
      |> Enum.filter(&(&1["type"] == "tool_use"))
      |> Enum.map(fn b ->
        %ToolCall{id: b["id"], name: b["name"], arguments: b["input"] || %{}}
      end)

    usage = resp["usage"] || %{}

    %Response{
      content: text,
      stop_reason: map_stop_reason(resp["stop_reason"]),
      tool_calls: tool_calls,
      usage: %{
        input_tokens: usage["input_tokens"] || 0,
        output_tokens: usage["output_tokens"] || 0
      },
      raw: resp
    }
  end

  defp map_stop_reason("end_turn"), do: :stop
  defp map_stop_reason("tool_use"), do: :tool_use
  defp map_stop_reason("max_tokens"), do: :length
  defp map_stop_reason(_), do: :stop
end
