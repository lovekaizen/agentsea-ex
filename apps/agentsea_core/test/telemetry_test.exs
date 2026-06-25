defmodule AgentSea.TelemetryTest do
  use ExUnit.Case, async: false

  import Mox

  alias AgentSea.{Agent, Response, ToolCall}
  alias AgentSea.Test.EchoTool

  setup :set_mox_global
  setup :verify_on_exit!

  defp start_agent(overrides \\ []) do
    base = [name: :tele, model: "claude-haiku-4-5", provider: {AgentSea.MockProvider, []}]
    start_supervised!({Agent, struct!(Agent.Config, Keyword.merge(base, overrides))})
  end

  test "telemetry events/0 lists agent, provider, tool and crew events" do
    events = AgentSea.Telemetry.events()
    assert [:agentsea, :agent, :run, :stop] in events
    assert [:agentsea, :provider, :complete, :stop] in events
    assert [:agentsea, :tool, :run, :exception] in events
    assert [:agentsea, :crew, :kickoff, :stop] in events
    assert [:agentsea, :crew, :task, :start] in events
  end

  test "emits agent-run and provider-complete spans with token usage" do
    expect(AgentSea.MockProvider, :complete, fn _messages, _opts ->
      {:ok,
       %Response{
         content: "hi",
         stop_reason: :stop,
         usage: %{input_tokens: 3, output_tokens: 1}
       }}
    end)

    ref =
      :telemetry_test.attach_event_handlers(self(), [
        [:agentsea, :agent, :run, :stop],
        [:agentsea, :provider, :complete, :stop]
      ])

    agent = start_agent()
    assert {:ok, _} = Agent.run(agent, "hi")

    assert_receive {[:agentsea, :provider, :complete, :stop], ^ref, %{duration: _},
                    %{model: "claude-haiku-4-5", outcome: :ok, output_tokens: 1, iteration: 0}}

    assert_receive {[:agentsea, :agent, :run, :stop], ^ref, %{duration: _},
                    %{name: :tele, outcome: :ok, stop_reason: :stop}}
  end

  test "emits a tool-run span" do
    AgentSea.MockProvider
    |> expect(:complete, fn _messages, _opts ->
      {:ok,
       %Response{
         stop_reason: :tool_use,
         tool_calls: [%ToolCall{id: "t", name: "echo", arguments: %{"text" => "x"}}]
       }}
    end)
    |> expect(:complete, fn _messages, _opts -> {:ok, %Response{content: "done"}} end)

    ref = :telemetry_test.attach_event_handlers(self(), [[:agentsea, :tool, :run, :stop]])

    agent = start_agent(tools: [EchoTool])
    assert {:ok, _} = Agent.run(agent, "echo please")

    assert_receive {[:agentsea, :tool, :run, :stop], ^ref, %{duration: _},
                    %{tool: "echo", agent: :tele, outcome: :ok}}
  end
end
