defmodule AgentSea.Crews.NoopProvider do
  @moduledoc """
  A provider that is never actually invoked. Bidding is pure (no completion
  call), so delegation tests only need a valid provider value in the agent
  config, not a real or mocked LLM.
  """

  @behaviour AgentSea.Provider

  @impl true
  def complete(_messages, _opts), do: {:error, :not_used}

  @impl true
  def model_info(_model), do: nil
end
