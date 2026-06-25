defmodule AgentSea.Surf do
  @moduledoc """
  Browser automation / computer use via a Node sidecar (`AgentSea.Surf.Sidecar`),
  plus an adapter that exposes browsing as agent tools.

  ## Example

      {:ok, surf} = AgentSea.Surf.start_link()   # spawns the priv Playwright server
      {:ok, _} = AgentSea.Surf.navigate(surf, "https://example.com")
      {:ok, text} = AgentSea.Surf.text(surf)

      # or expose it to an agent:
      tools = AgentSea.Surf.tool_specs(surf)
  """

  alias AgentSea.Surf.Sidecar

  @doc """
  Start a sidecar. Defaults to running the bundled Playwright server with `node`
  (requires `playwright` installed on the Node side); pass `:command` to run a
  different script or executable.
  """
  def start_link(opts \\ []) do
    command = Keyword.get(opts, :command, ["node", default_server()])
    Sidecar.start_link(Keyword.put(opts, :command, command))
  end

  @doc "Path to the bundled Playwright-backed Node server."
  def default_server, do: Application.app_dir(:agentsea_surf, "priv/surf-server.js")

  # --- Browser commands ---

  def navigate(server, url), do: Sidecar.call(server, "navigate", %{"url" => url})
  def text(server), do: Sidecar.call(server, "text", %{})
  def screenshot(server), do: Sidecar.call(server, "screenshot", %{})
  def click(server, selector), do: Sidecar.call(server, "click", %{"selector" => selector})
  def eval(server, script), do: Sidecar.call(server, "eval", %{"script" => script})

  # --- Agent tool adapter ---

  @doc "Build `AgentSea.Tool.Spec` browser tools bound to a running sidecar."
  @spec tool_specs(GenServer.server()) :: [AgentSea.Tool.Spec.t()]
  def tool_specs(server) do
    [
      %AgentSea.Tool.Spec{
        name: "browse",
        description: "Open a URL in a browser and return the page's visible text.",
        schema: [url: [type: :string, required: true]],
        run: fn args, _ctx ->
          with {:ok, _} <- navigate(server, arg(args, :url)),
               {:ok, text} <- text(server) do
            {:ok, text}
          end
        end
      },
      %AgentSea.Tool.Spec{
        name: "click",
        description: "Click an element by CSS selector on the current page.",
        schema: [selector: [type: :string, required: true]],
        run: fn args, _ctx -> click(server, arg(args, :selector)) end
      }
    ]
  end

  defp arg(args, key), do: Map.get(args, to_string(key)) || Map.get(args, key)
end
