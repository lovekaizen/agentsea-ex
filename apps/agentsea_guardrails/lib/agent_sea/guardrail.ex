defmodule AgentSea.Guardrail do
  @moduledoc """
  A check applied to text entering or leaving an agent. Each guardrail either
  passes (`:ok`), rewrites the content (`{:transform, new}` — e.g. redaction), or
  blocks it (`{:block, reason}`). `AgentSea.Guardrails` chains them.

  Built-ins: `MaxLength`, `Blocklist`, `PIIRedactor`, and the provider-backed
  `LLMGuard`.
  """

  @type outcome :: :ok | {:transform, String.t()} | {:block, reason :: term()}

  @callback name() :: String.t()
  @callback check(content :: String.t(), opts :: keyword()) :: outcome()
end
