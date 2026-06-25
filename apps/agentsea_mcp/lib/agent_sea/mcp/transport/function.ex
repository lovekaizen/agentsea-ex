defmodule AgentSea.MCP.Transport.Function do
  @moduledoc """
  A transport backed by a 2-arity function `(method, params) -> {:ok, result} |
  {:error, reason}`. Handy for in-process MCP servers, tests, and demos. The
  client's `ref` is the function itself.
  """

  @behaviour AgentSea.MCP.Transport

  @impl true
  def request(fun, method, params) when is_function(fun, 2) do
    fun.(method, params)
  end
end
