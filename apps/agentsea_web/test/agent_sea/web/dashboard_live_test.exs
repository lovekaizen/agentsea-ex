defmodule AgentSea.Web.DashboardLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint AgentSea.Web.Endpoint

  setup do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  test "mounts and renders the dashboard with zeroed stats", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert html =~ "AgentSea Dashboard"
    assert render(view) =~ "Agent runs: 0"
    assert render(view) =~ "Tokens: 0"
  end

  test "updates token totals when a provider event is emitted", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    :telemetry.execute(
      [:agentsea, :provider, :complete, :stop],
      %{duration: 1},
      %{model: "m", outcome: :ok, input_tokens: 10, output_tokens: 5}
    )

    html = render(view)
    assert html =~ "Tokens: 15"
    assert html =~ "agentsea.provider.complete.stop"
  end

  test "increments the agent-run and crew counters", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    :telemetry.execute([:agentsea, :agent, :run, :stop], %{duration: 1}, %{
      name: :a,
      outcome: :ok
    })

    :telemetry.execute([:agentsea, :crew, :kickoff, :stop], %{duration: 1}, %{
      crew: :c,
      success: true
    })

    html = render(view)
    assert html =~ "Agent runs: 1"
    assert html =~ "Crews: 1"
  end

  test "counts guardrail blocks (but not transforms)", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    :telemetry.execute([:agentsea, :guardrail, :stop], %{system_time: 1}, %{
      guardrail: "pii_redactor",
      outcome: :transform
    })

    :telemetry.execute([:agentsea, :guardrail, :stop], %{system_time: 1}, %{
      guardrail: "blocklist",
      outcome: :block
    })

    html = render(view)
    # The transform shows in the feed but only the block increments the counter.
    assert html =~ "Guardrail blocks: 1"
    assert html =~ "agentsea.guardrail.stop"
  end
end
