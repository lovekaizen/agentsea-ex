defmodule AgentSea.Memory.BufferTest do
  # async: false — the buffer registers under its module name.
  use ExUnit.Case, async: false

  alias AgentSea.Memory.Buffer

  setup do
    start_supervised!({Buffer, max_messages: 3})
    :ok
  end

  test "saves and loads messages per conversation" do
    assert Buffer.load("c1") == []
    assert :ok = Buffer.save("c1", [%{role: :user, content: "hi"}])
    assert [%{content: "hi"}] = Buffer.load("c1")
    # Different conversations are isolated.
    assert Buffer.load("c2") == []
  end

  test "append adds to existing history" do
    Buffer.save("c1", [%{role: :user, content: "a"}])
    Buffer.append("c1", [%{role: :assistant, content: "b"}])
    assert ["a", "b"] = Buffer.load("c1") |> Enum.map(& &1.content)
  end

  test "enforces the max window" do
    msgs = for i <- 1..5, do: %{role: :user, content: "m#{i}"}
    Buffer.save("c1", msgs)
    # Only the last 3 are kept.
    assert ["m3", "m4", "m5"] = Buffer.load("c1") |> Enum.map(& &1.content)
  end

  test "clear empties a conversation" do
    Buffer.save("c1", [%{role: :user, content: "x"}])
    assert :ok = Buffer.clear("c1")
    assert Buffer.load("c1") == []
  end
end
