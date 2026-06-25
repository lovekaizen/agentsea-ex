defmodule AgentSea.Memory do
  @moduledoc """
  Conversation memory. Adapters (buffer, summary, vector) implement this
  behaviour. `search/2` is optional (only vector-backed stores implement it).
  """

  @type conversation_id :: String.t()
  @type message :: AgentSea.Provider.message()

  @callback save(conversation_id(), [message()]) :: :ok
  @callback load(conversation_id()) :: [message()]
  @callback clear(conversation_id()) :: :ok
  @callback search(query :: String.t(), limit :: pos_integer()) :: [message()]

  @optional_callbacks search: 2
end
