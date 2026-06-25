defmodule AgentSea.Gateway.StreamTest do
  use ExUnit.Case, async: false

  alias AgentSea.Gateway
  alias AgentSea.Gateway.{Config, Provider}
  alias AgentSea.Gateway.Router.Failover
  alias AgentSea.Gateway.TestProvider

  defp pname(prefix), do: :"#{prefix}_#{System.unique_integer([:positive])}"

  test "streams events from the selected provider" do
    p = %Provider{
      name: pname(:s),
      module: TestProvider,
      model: "m",
      opts: [behavior: :ok, tag: "hello world stream"]
    }

    gw = start_supervised!({Gateway, %Config{providers: [p], strategy: Failover}})

    assert {:ok, stream, name} = Gateway.stream(gw, [])
    assert name == p.name

    events = Enum.to_list(stream)
    assert {:content, "hello"} in events
    assert :done in events

    contents = for {:content, word} <- events, do: word
    assert Enum.join(contents, " ") == "hello world stream"
  end

  test "errors when no provider is available" do
    gw = start_supervised!({Gateway, %Config{providers: [], strategy: Failover}})
    assert {:error, :all_providers_unavailable} = Gateway.stream(gw, [])
  end
end
