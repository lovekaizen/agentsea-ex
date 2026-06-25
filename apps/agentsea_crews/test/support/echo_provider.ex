defmodule AgentSea.Crews.EchoProvider do
  @moduledoc """
  A deterministic provider for crew tests: echoes the last user message as the
  completion. If the input contains "FAIL", it returns an error so failure paths
  can be exercised.
  """

  @behaviour AgentSea.Provider
  alias AgentSea.Response

  @impl true
  def complete(messages, _opts) do
    last_user =
      messages
      |> Enum.reverse()
      |> Enum.find(%{content: ""}, &(&1.role == :user))

    content = to_string(last_user.content)

    if String.contains?(content, "FAIL") do
      {:error, :forced_failure}
    else
      {:ok, %Response{content: "handled: #{content}", stop_reason: :stop}}
    end
  end

  @impl true
  def model_info(_model), do: nil
end
