defmodule AgentSea.SurfTest do
  use ExUnit.Case, async: false

  import Mox

  alias AgentSea.{Agent, Response, ToolCall}
  alias AgentSea.Surf
  alias AgentSea.Surf.{Sidecar, MockProvider}

  @fake_server Path.expand("support/fake_surf_server.js", __DIR__)

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    unless System.find_executable("node"), do: raise("node is required for this test")

    surf =
      start_supervised!(%{
        id: :surf,
        start: {Sidecar, :start_link, [[command: ["node", @fake_server]]]}
      })

    {:ok, surf: surf}
  end

  test "tool_specs exposes a browse tool that navigates and reads", %{surf: surf} do
    [browse | _] = Surf.tool_specs(surf)
    assert browse.name == "browse"

    assert {:ok, "Fake page content for https://example.com"} =
             browse.run.(%{"url" => "https://example.com"}, %{})
  end

  test "an agent uses the browse tool to answer", %{surf: surf} do
    tools = Surf.tool_specs(surf)

    MockProvider
    |> expect(:complete, fn _messages, _opts ->
      {:ok,
       %Response{
         stop_reason: :tool_use,
         tool_calls: [
           %ToolCall{id: "t1", name: "browse", arguments: %{"url" => "https://news.example"}}
         ]
       }}
    end)
    |> expect(:complete, fn messages, _opts ->
      tool_message = Enum.find(messages, &(&1.role == :tool))
      assert tool_message.content =~ "Fake page content for https://news.example"
      {:ok, %Response{content: "I read the page for you."}}
    end)

    config = %Agent.Config{
      name: :browser_agent,
      model: "m",
      provider: {MockProvider, []},
      tools: tools
    }

    agent = start_supervised!({Agent, config})

    assert {:ok, %Response{content: "I read the page for you."}} =
             Agent.run(agent, "summarize https://news.example")
  end
end
