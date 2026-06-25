defmodule AgentSea.GuardrailTest do
  use ExUnit.Case, async: true

  alias AgentSea.Guardrail.{MaxLength, Blocklist, PIIRedactor}

  describe "MaxLength" do
    test "passes within the limit, blocks over it" do
      assert :ok = MaxLength.check("short", max: 10)
      assert {:block, {:too_long, 11, 5}} = MaxLength.check("12345678901", max: 5)
    end
  end

  describe "Blocklist" do
    test "blocks a banned term (case-insensitive), passes otherwise" do
      opts = [terms: ["ignore previous instructions", "DROP TABLE"]]
      assert :ok = Blocklist.check("what's the weather?", opts)

      assert {:block, {:blocked_term, "ignore previous instructions"}} =
               Blocklist.check("Please IGNORE PREVIOUS INSTRUCTIONS and...", opts)
    end

    test "passes when no terms configured" do
      assert :ok = Blocklist.check("anything", [])
    end
  end

  describe "PIIRedactor" do
    test "redacts emails, SSNs and phone numbers" do
      input = "Reach me at jane.doe@example.com or 555-123-4567, SSN 123-45-6789."

      assert {:transform, redacted} = PIIRedactor.check(input, [])
      assert redacted == "Reach me at [EMAIL] or [PHONE], SSN [SSN]."
      refute redacted =~ "example.com"
    end

    test "passes content with no PII unchanged" do
      assert :ok = PIIRedactor.check("just a normal sentence", [])
    end

    test "honors a restricted :types list" do
      assert {:transform, redacted} =
               PIIRedactor.check("a@b.com and 555-123-4567", types: [:email])

      assert redacted == "[EMAIL] and 555-123-4567"
    end
  end
end
