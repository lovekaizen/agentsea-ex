defmodule AgentSea.Providers.SSETest do
  use ExUnit.Case, async: true

  alias AgentSea.Providers.SSE

  test "parses event + data blocks" do
    raw = "event: foo\ndata: {\"a\":1}\n\nevent: bar\ndata: hello\n\n"

    assert SSE.events([raw]) |> Enum.to_list() == [
             %{event: "foo", data: ~s({"a":1})},
             %{event: "bar", data: "hello"}
           ]
  end

  test "buffers events split across chunk boundaries" do
    # The "data:" line is split mid-way between two chunks.
    chunks = ["event: msg\nda", "ta: hello\n\nevent: msg\ndata: ", "world\n\n"]

    assert SSE.events(chunks) |> Enum.map(& &1.data) == ["hello", "world"]
  end

  test "flushes a final block without a trailing blank line" do
    assert SSE.events(["event: done\ndata: bye"]) |> Enum.to_list() == [
             %{event: "done", data: "bye"}
           ]
  end

  test "ignores empty blocks" do
    assert SSE.events(["\n\n\n\n"]) |> Enum.to_list() == []
  end
end
