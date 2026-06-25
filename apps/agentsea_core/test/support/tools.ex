defmodule AgentSea.Test.EchoTool do
  @moduledoc "A trivial tool that echoes its `text` argument. Used in tests."
  @behaviour AgentSea.Tool

  @impl true
  def name, do: "echo"
  @impl true
  def description, do: "Echoes back the provided text."
  @impl true
  def schema, do: [text: [type: :string, required: true]]

  @impl true
  def run(%{"text" => text}, _ctx), do: {:ok, "echo: #{text}"}
  def run(args, _ctx), do: {:ok, "echo: #{inspect(args)}"}
end

defmodule AgentSea.Test.CrashTool do
  @moduledoc "A tool that always raises. Used to test crash isolation."
  @behaviour AgentSea.Tool

  @impl true
  def name, do: "crash"
  @impl true
  def description, do: "Always raises."
  @impl true
  def schema, do: []

  @impl true
  def run(_args, _ctx), do: raise("boom")
end
