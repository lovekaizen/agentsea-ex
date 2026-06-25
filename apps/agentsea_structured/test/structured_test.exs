defmodule AgentSea.StructuredTest do
  use ExUnit.Case, async: true

  import Mox

  alias AgentSea.Structured
  alias AgentSea.Structured.TestSchemas.Person
  alias AgentSea.Response

  setup :verify_on_exit!

  defp ok(content),
    do: {:ok, %Response{content: content, stop_reason: :stop}}

  defp extract(input \\ "Ada Lovelace, 36", opts \\ []) do
    Structured.extract(
      Person,
      input,
      Keyword.merge([provider: {AgentSea.Structured.MockProvider, []}, model: "m"], opts)
    )
  end

  test "extracts a validated struct from clean JSON" do
    expect(AgentSea.Structured.MockProvider, :complete, fn _messages, opts ->
      assert opts[:model] == "m"
      ok(~s({"name": "Ada", "age": 36}))
    end)

    assert {:ok, %Person{name: "Ada", age: 36}} = extract()
  end

  test "includes the field list in the system prompt" do
    expect(AgentSea.Structured.MockProvider, :complete, fn messages, _opts ->
      system = Enum.find(messages, &(&1.role == :system)).content
      assert system =~ "name: string"
      assert system =~ "age: integer"
      ok(~s({"name": "Ada", "age": 36}))
    end)

    assert {:ok, %Person{}} = extract()
  end

  test "extracts JSON embedded in prose / code fences" do
    expect(AgentSea.Structured.MockProvider, :complete, fn _messages, _opts ->
      ok("Sure! Here you go:\n```json\n{\"name\": \"Bob\", \"age\": 40}\n```")
    end)

    assert {:ok, %Person{name: "Bob", age: 40}} = extract()
  end

  test "retries with a validation hint, then succeeds" do
    AgentSea.Structured.MockProvider
    |> expect(:complete, fn _messages, _opts -> ok(~s({"name": "X", "age": -1})) end)
    |> expect(:complete, fn messages, _opts ->
      # The second attempt must carry the validation feedback.
      last = List.last(messages)
      assert last.role == :user
      assert last.content =~ "failed validation"
      ok(~s({"name": "X", "age": 5}))
    end)

    assert {:ok, %Person{age: 5}} = extract()
  end

  test "retries on invalid JSON" do
    AgentSea.Structured.MockProvider
    |> expect(:complete, fn _messages, _opts -> ok("definitely not json") end)
    |> expect(:complete, fn messages, _opts ->
      assert List.last(messages).content =~ "not valid JSON"
      ok(~s({"name": "Y", "age": 1}))
    end)

    assert {:ok, %Person{name: "Y"}} = extract()
  end

  test "returns a validation error after exhausting retries" do
    # Always missing :age → fails required validation every time.
    stub(AgentSea.Structured.MockProvider, :complete, fn _messages, _opts ->
      ok(~s({"name": "Z"}))
    end)

    assert {:error, {:validation, errors}} = extract("Z", max_retries: 1)
    assert %{age: _} = errors
  end

  test "surfaces a provider error" do
    expect(AgentSea.Structured.MockProvider, :complete, fn _messages, _opts ->
      {:error, :rate_limited}
    end)

    assert {:error, :rate_limited} = extract()
  end
end
