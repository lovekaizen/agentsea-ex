defmodule AgentSea.Providers.SSE do
  @moduledoc """
  Frames a stream of raw HTTP body chunks into Server-Sent Events.

  Pure and lazy: it buffers across chunk boundaries (an event may be split mid-
  way between two network reads) and emits one map per complete event with its
  `:event` name (if any) and concatenated `:data` payload.
  """

  @type event :: %{event: String.t() | nil, data: String.t()}

  @doc "Turn an enumerable of binary chunks into a lazy stream of `t:event/0`."
  @spec events(Enumerable.t()) :: Enumerable.t()
  def events(chunks) do
    chunks
    # ensure the final block is flushed even without a trailing blank line
    |> Stream.concat(["\n\n"])
    |> Stream.transform("", fn chunk, buffer ->
      split_blocks(buffer <> chunk)
    end)
    |> Stream.map(&parse_block/1)
    |> Stream.reject(&is_nil/1)
  end

  # Returns {complete_event_blocks, leftover_buffer}.
  defp split_blocks(buffer) do
    parts = String.split(buffer, "\n\n")
    {complete, [rest]} = Enum.split(parts, length(parts) - 1)
    {complete, rest}
  end

  defp parse_block(block) do
    lines =
      block
      |> String.split("\n")
      |> Enum.map(&String.trim_trailing(&1, "\r"))

    event =
      Enum.find_value(lines, fn
        "event:" <> rest -> String.trim(rest)
        _ -> nil
      end)

    data =
      lines
      |> Enum.filter(&String.starts_with?(&1, "data:"))
      |> Enum.map_join("\n", fn "data:" <> rest -> String.trim_leading(rest) end)

    if data == "" and is_nil(event), do: nil, else: %{event: event, data: data}
  end
end
