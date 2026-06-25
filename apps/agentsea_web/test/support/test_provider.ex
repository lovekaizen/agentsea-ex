defmodule AgentSea.Web.TestProvider do
  @moduledoc "A deterministic provider for the OpenAI-compatible endpoint tests."

  @behaviour AgentSea.Provider
  alias AgentSea.Response

  @impl true
  def complete(_messages, _opts) do
    {:ok,
     %Response{
       content: "Hello there friend",
       stop_reason: :stop,
       usage: %{input_tokens: 7, output_tokens: 3}
     }}
  end

  @impl true
  def model_info(_model), do: nil
end
