defmodule AgentSea.CapabilityTest do
  use ExUnit.Case, async: true

  alias AgentSea.Capability

  defp cap(name, proficiency), do: %Capability{name: name, proficiency: proficiency}

  test "proficiency_score maps levels to weights" do
    assert Capability.proficiency_score(cap("x", :novice)) == 0.25
    assert Capability.proficiency_score(cap("x", :master)) == 1.0
  end

  test "full match: can_execute and score reflects proficiency" do
    caps = [cap("coding", :expert), cap("design", :master)]
    m = Capability.match(caps, ["coding", "design"])

    assert m.can_execute
    assert m.missing == []
    assert Enum.sort(m.matched) == ["coding", "design"]
    # coverage 1.0 * avg(0.75, 1.0) = 0.875
    assert m.score == 0.875
  end

  test "partial match: missing capability means cannot execute, lower score" do
    caps = [cap("coding", :expert)]
    m = Capability.match(caps, ["coding", "design"])

    refute m.can_execute
    assert m.matched == ["coding"]
    assert m.missing == ["design"]
    # coverage 0.5 * avg(0.75) = 0.375
    assert m.score == 0.375
  end

  test "no required capabilities: can_execute, score is overall proficiency" do
    caps = [cap("coding", :expert), cap("design", :intermediate)]
    m = Capability.match(caps, [])

    assert m.can_execute
    assert m.matched == []
    # avg(0.75, 0.5)
    assert m.score == 0.625
  end

  test "empty agent with no requirement scores zero but can execute" do
    m = Capability.match([], [])
    assert m.can_execute
    assert m.score == 0.0
  end
end
