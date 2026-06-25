defmodule AgentSea.Providers.AnthropicStreamTest do
  use ExUnit.Case, async: true

  alias AgentSea.Providers.Anthropic

  # A realistic Anthropic Messages streaming response.
  @sse """
  event: message_start
  data: {"type":"message_start","message":{"id":"msg_1"}}

  event: content_block_start
  data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

  event: ping
  data: {"type":"ping"}

  event: content_block_delta
  data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

  event: content_block_delta
  data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" world"}}

  event: content_block_stop
  data: {"type":"content_block_stop","index":0}

  event: message_delta
  data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}

  event: message_stop
  data: {"type":"message_stop"}

  """

  # Split the payload into small fixed-size chunks to exercise cross-chunk
  # buffering in the SSE framer.
  defp byte_chunks(binary, size) do
    binary
    |> :binary.bin_to_list()
    |> Enum.chunk_every(size)
    |> Enum.map(&:erlang.list_to_binary/1)
  end

  test "normalizes Anthropic SSE into content deltas + :done" do
    events =
      Anthropic.stream([], body_stream: byte_chunks(@sse, 24), model: "claude-haiku-4-5")
      |> Enum.to_list()

    assert events == [{:content, "Hello"}, {:content, " world"}, :done]
  end

  test "maps thinking deltas to {:thinking, _}" do
    sse = """
    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"hmm"}}

    event: message_stop
    data: {"type":"message_stop"}

    """

    assert Anthropic.stream([], body_stream: [sse], model: "m") |> Enum.to_list() ==
             [{:thinking, "hmm"}, :done]
  end
end
