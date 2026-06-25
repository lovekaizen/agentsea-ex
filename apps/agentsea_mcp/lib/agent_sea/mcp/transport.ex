defmodule AgentSea.MCP.Transport do
  @moduledoc """
  Request/response transport for the MCP JSON-RPC protocol. The client is
  transport-agnostic; real transports (stdio over a Port, streamable HTTP/SSE
  over Req) and the in-process `AgentSea.MCP.Transport.Function` all implement
  this one callback.
  """

  @callback request(ref :: term(), method :: String.t(), params :: map()) ::
              {:ok, map()} | {:error, term()}
end
