defmodule AgentSea.Crews.BlockingProvider do
  @moduledoc """
  A provider that holds a task in-flight so pause/resume/abort can be observed
  deterministically. On `complete/2` it sends `{:running, self(), content}` to
  the `:notify` pid, then blocks until it receives `:release`.
  """

  @behaviour AgentSea.Provider
  alias AgentSea.Response

  @impl true
  def complete(messages, opts) do
    notify = Keyword.fetch!(opts, :notify)

    content =
      messages
      |> Enum.reverse()
      |> Enum.find(%{content: ""}, &(&1.role == :user))
      |> Map.get(:content)
      |> to_string()

    send(notify, {:running, self(), content})

    receive do
      :release -> {:ok, %Response{content: "handled: #{content}", stop_reason: :stop}}
    after
      10_000 -> {:error, :timeout}
    end
  end

  @impl true
  def model_info(_model), do: nil
end
