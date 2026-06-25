defmodule AgentSea.Surf.SidecarTest do
  use ExUnit.Case, async: false

  alias AgentSea.Surf
  alias AgentSea.Surf.Sidecar

  @fake_server Path.expand("support/fake_surf_server.js", __DIR__)

  setup do
    unless System.find_executable("node"), do: raise("node is required for this test")

    surf =
      start_supervised!(%{
        id: :surf,
        start: {Sidecar, :start_link, [[command: ["node", @fake_server]]]}
      })

    {:ok, surf: surf}
  end

  test "navigate then read returns the page text", %{surf: surf} do
    assert {:ok, %{"url" => "https://example.com"}} = Surf.navigate(surf, "https://example.com")
    assert {:ok, "Fake page content for https://example.com"} = Surf.text(surf)
  end

  test "screenshot, click and eval round-trip over stdio", %{surf: surf} do
    assert {:ok, %{"base64" => b64}} = Surf.screenshot(surf)
    assert is_binary(b64)
    assert {:ok, %{"clicked" => "#submit"}} = Surf.click(surf, "#submit")
    assert {:ok, "evaluated"} = Surf.eval(surf, "1 + 1")
  end

  test "unknown commands surface as errors", %{surf: surf} do
    assert {:error, "unknown command: fly"} = Sidecar.call(surf, "fly", %{})
  end

  test "concurrent commands are correlated by id", %{surf: surf} do
    # Fire several in parallel; each must get its own correct response.
    results =
      1..10
      |> Task.async_stream(fn i -> Surf.navigate(surf, "https://site/#{i}") end, max_concurrency: 10)
      |> Enum.map(fn {:ok, {:ok, %{"url" => url}}} -> url end)
      |> Enum.sort()

    assert results == Enum.sort(for i <- 1..10, do: "https://site/#{i}")
  end
end
