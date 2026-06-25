defmodule AgentSea.AgentTest do
  # async: false because the agent runs in its own process and consumes Mox
  # expectations in global mode.
  use ExUnit.Case, async: false

  import Mox

  alias AgentSea.{Agent, Response, ToolCall}
  alias AgentSea.Test.{EchoTool, CrashTool}

  setup :set_mox_global
  setup :verify_on_exit!

  defp config(overrides) do
    base = [
      name: :tester,
      model: "mock-model",
      provider: {AgentSea.MockProvider, []}
    ]

    struct!(Agent.Config, Keyword.merge(base, overrides))
  end

  defp start_agent(overrides \\ []) do
    start_supervised!({Agent, config(overrides)})
  end

  test "returns the provider completion when there are no tool calls" do
    expect(AgentSea.MockProvider, :complete, fn _messages, _opts ->
      {:ok, %Response{content: "Hello!", stop_reason: :stop}}
    end)

    agent = start_agent()
    assert {:ok, %Response{content: "Hello!"}} = Agent.run(agent, "hi")
  end

  test "passes model + system prompt through to the provider" do
    expect(AgentSea.MockProvider, :complete, fn messages, opts ->
      assert opts[:model] == "mock-model"
      assert opts[:system_prompt] == "You are helpful."
      assert [%{role: :system}, %{role: :user, content: "hi"}] = messages
      {:ok, %Response{content: "ok"}}
    end)

    agent = start_agent(system_prompt: "You are helpful.")
    assert {:ok, %Response{content: "ok"}} = Agent.run(agent, "hi")
  end

  test "runs a requested tool then completes, feeding the result back" do
    AgentSea.MockProvider
    |> expect(:complete, fn _messages, _opts ->
      {:ok,
       %Response{
         content: "",
         stop_reason: :tool_use,
         tool_calls: [%ToolCall{id: "t1", name: "echo", arguments: %{"text" => "ping"}}]
       }}
    end)
    |> expect(:complete, fn messages, _opts ->
      # The tool result must have been appended before the second call.
      assert Enum.any?(messages, fn m ->
               m.role == :tool and m.content == "echo: ping"
             end)

      {:ok, %Response{content: "done"}}
    end)

    agent = start_agent(tools: [EchoTool])
    assert {:ok, %Response{content: "done"}} = Agent.run(agent, "please echo")
  end

  @tag :capture_log
  test "folds a crashing tool into an error result and keeps going" do
    AgentSea.MockProvider
    |> expect(:complete, fn _messages, _opts ->
      {:ok,
       %Response{
         stop_reason: :tool_use,
         tool_calls: [%ToolCall{id: "c1", name: "crash", arguments: %{}}]
       }}
    end)
    |> expect(:complete, fn messages, _opts ->
      tool_msg = Enum.find(messages, &(&1.role == :tool))
      assert tool_msg.content =~ "Error:"
      assert tool_msg.content =~ "tool_crashed"
      {:ok, %Response{content: "recovered"}}
    end)

    agent = start_agent(tools: [CrashTool])
    # The agent process must survive the tool crash.
    assert {:ok, %Response{content: "recovered"}} = Agent.run(agent, "do it")
    assert Process.alive?(agent)
  end

  test "reports an unknown tool as an error result (does not crash)" do
    AgentSea.MockProvider
    |> expect(:complete, fn _messages, _opts ->
      {:ok,
       %Response{
         stop_reason: :tool_use,
         tool_calls: [%ToolCall{id: "u1", name: "nope", arguments: %{}}]
       }}
    end)
    |> expect(:complete, fn messages, _opts ->
      assert Enum.find(messages, &(&1.role == :tool)).content =~ "unknown_tool"
      {:ok, %Response{content: "ok"}}
    end)

    agent = start_agent(tools: [EchoTool])
    assert {:ok, %Response{content: "ok"}} = Agent.run(agent, "x")
  end

  test "stops at max_iterations when the model never stops calling tools" do
    stub(AgentSea.MockProvider, :complete, fn _messages, _opts ->
      {:ok,
       %Response{
         stop_reason: :tool_use,
         tool_calls: [%ToolCall{id: "t", name: "echo", arguments: %{"text" => "x"}}]
       }}
    end)

    agent = start_agent(tools: [EchoTool], max_iterations: 2)
    assert {:error, {:max_iterations, _messages}} = Agent.run(agent, "loop forever")
  end

  test "accumulates history across runs" do
    stub(AgentSea.MockProvider, :complete, fn _messages, _opts ->
      {:ok, %Response{content: "reply"}}
    end)

    agent = start_agent()
    assert {:ok, _} = Agent.run(agent, "first")
    assert {:ok, _} = Agent.run(agent, "second")

    history = Agent.history(agent)
    user_messages = Enum.filter(history, &(&1.role == :user))
    assert Enum.map(user_messages, & &1.content) == ["first", "second"]

    assert :ok = Agent.reset(agent)
    assert Agent.history(agent) == []
  end
end
