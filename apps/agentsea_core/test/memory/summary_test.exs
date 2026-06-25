defmodule AgentSea.Memory.SummaryTest do
  use ExUnit.Case, async: false

  import Mox

  alias AgentSea.Memory.Summary
  alias AgentSea.Response

  setup :set_mox_global
  setup :verify_on_exit!

  defp start(opts \\ []) do
    base = [provider: {AgentSea.MockProvider, []}, model: "m", keep_recent: 2, threshold: 4]
    start_supervised!({Summary, Keyword.merge(base, opts)})
  end

  defp msgs(n), do: for(i <- 1..n, do: %{role: :user, content: "message #{i}"})

  test "under the threshold, load returns messages verbatim (no LLM call)" do
    start()
    # No provider expectation — must not summarize.
    :ok = Summary.save("c1", msgs(3))
    assert Summary.load("c1") == msgs(3)
  end

  test "over the threshold, older messages are summarized and prepended" do
    expect(AgentSea.MockProvider, :complete, fn messages, opts ->
      assert opts[:model] == "m"
      # The transcript of the older messages is summarized.
      assert Enum.any?(messages, &(&1.role == :user and &1.content =~ "message 1"))
      {:ok, %Response{content: "They discussed messages 1-4.", stop_reason: :stop}}
    end)

    start()
    :ok = Summary.save("c1", msgs(6))

    assert [summary | recent] = Summary.load("c1")
    assert summary.role == :system
    assert summary.content == "Summary of earlier conversation: They discussed messages 1-4."
    # keep_recent: 2 → the last two verbatim
    assert recent == [%{role: :user, content: "message 5"}, %{role: :user, content: "message 6"}]
  end

  test "clear removes a conversation" do
    start()
    :ok = Summary.save("c1", msgs(2))
    assert Summary.load("c1") == msgs(2)
    assert :ok = Summary.clear("c1")
    assert Summary.load("c1") == []
  end

  test "falls back to no summary if the provider errors" do
    stub(AgentSea.MockProvider, :complete, fn _m, _o -> {:error, :down} end)
    start()
    :ok = Summary.save("c1", msgs(6))

    # No summary message; just the recent tail.
    assert Summary.load("c1") == [
             %{role: :user, content: "message 5"},
             %{role: :user, content: "message 6"}
           ]
  end
end
