defmodule AgentSea.GuardrailsTest do
  use ExUnit.Case, async: true

  alias AgentSea.Guardrails
  alias AgentSea.Guardrail.{MaxLength, Blocklist, PIIRedactor}

  test "passes content through an empty pipeline unchanged" do
    assert {:ok, "hello"} = Guardrails.run("hello", [])
  end

  test "a transform updates the content seen by later guardrails" do
    # PII redaction happens first; the blocklist then sees the redacted text.
    pipeline = [PIIRedactor, {Blocklist, terms: ["@"]}]
    assert {:ok, "email [EMAIL] ok"} = Guardrails.run("email a@b.com ok", pipeline)
  end

  test "the first block short-circuits and names the guardrail" do
    pipeline = [
      {MaxLength, max: 100},
      {Blocklist, terms: ["forbidden"]},
      PIIRedactor
    ]

    assert {:block, {"blocklist", {:blocked_term, "forbidden"}}} =
             Guardrails.run("this is forbidden content", pipeline)
  end

  test "blocks on the earliest failing guardrail" do
    pipeline = [{MaxLength, max: 3}, {Blocklist, terms: ["x"]}]
    assert {:block, {"max_length", {:too_long, 5, 3}}} = Guardrails.run("hello", pipeline)
  end

  test "accepts bare-module guardrails (no opts)" do
    assert {:ok, "[EMAIL]"} = Guardrails.run("me@here.io", [PIIRedactor])
  end
end
