defmodule AgentSea.Gateway.TestProvider do
  @moduledoc """
  A configurable provider for gateway tests. Behavior is driven by the opts a
  candidate carries:

    * `behavior: :ok` (default) → returns a Response tagged with `:tag`
    * `behavior: :error` → returns `{:error, reason}`
    * `sleep_ms: n` → blocks before responding (to exercise latency routing)
  """

  @behaviour AgentSea.Provider
  alias AgentSea.Response

  @impl true
  def complete(_messages, opts) do
    if ms = opts[:sleep_ms], do: Process.sleep(ms)

    case opts[:behavior] do
      :error ->
        {:error, opts[:reason] || :boom}

      _ ->
        {:ok, %Response{content: opts[:tag] || "ok", stop_reason: :stop}}
    end
  end

  @impl true
  def stream(_messages, opts) do
    tag = opts[:tag] || "ok"

    (tag |> String.split(" ", trim: true) |> Enum.map(&{:content, &1})) ++ [:done]
  end

  @impl true
  def model_info(_model), do: nil
end
