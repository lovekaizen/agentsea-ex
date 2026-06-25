defmodule AgentSea.Guardrails.TelemetryTest do
  use ExUnit.Case, async: true

  alias AgentSea.Guardrails

  # Uniquely-named guardrails so this test's telemetry handler (a global
  # :telemetry handler) doesn't confuse events from other concurrent tests that
  # emit [:agentsea, :guardrail, :stop] with the built-in guardrail names.
  defmodule TransformGuard do
    @behaviour AgentSea.Guardrail
    @impl true
    def name, do: "tt_transform"
    @impl true
    def check(_content, _opts), do: {:transform, "redacted"}
  end

  defmodule BlockGuard do
    @behaviour AgentSea.Guardrail
    @impl true
    def name, do: "tt_block"
    @impl true
    def check(_content, _opts), do: {:block, :nope}
  end

  defmodule PassGuard do
    @behaviour AgentSea.Guardrail
    @impl true
    def name, do: "tt_pass"
    @impl true
    def check(_content, _opts), do: :ok
  end

  setup do
    ref = :telemetry_test.attach_event_handlers(self(), [[:agentsea, :guardrail, :stop]])
    on_exit(fn -> :telemetry.detach(ref) end)
    :ok
  end

  test "emits a :transform event when a guardrail rewrites content" do
    assert {:ok, "redacted"} = Guardrails.run("anything", [TransformGuard])

    assert_received {[:agentsea, :guardrail, :stop], _ref, _measurements,
                     %{guardrail: "tt_transform", outcome: :transform}}
  end

  test "emits a :block event when a guardrail blocks content" do
    assert {:block, {"tt_block", :nope}} = Guardrails.run("anything", [BlockGuard])

    assert_received {[:agentsea, :guardrail, :stop], _ref, _measurements,
                     %{guardrail: "tt_block", outcome: :block}}
  end

  test "stays silent on a plain pass" do
    assert {:ok, "fine"} = Guardrails.run("fine", [PassGuard])
    refute_received {[:agentsea, :guardrail, :stop], _, _, %{guardrail: "tt_pass"}}
  end
end
