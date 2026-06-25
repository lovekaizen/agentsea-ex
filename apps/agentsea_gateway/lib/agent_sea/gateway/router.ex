defmodule AgentSea.Gateway.Router do
  @moduledoc """
  Routing-strategy behaviour. A strategy *orders* the available candidates; the
  gateway then tries them in that order, failing over to the next when one
  errors. Strategies are pure — they receive the candidates and a context
  (`:counter`, live `:health`) and return a reordered list.
  """

  @typedoc "A configured provider candidate."
  @type candidate :: %{
          required(:name) => term(),
          required(:module) => module(),
          required(:model) => String.t(),
          optional(:opts) => keyword()
        }

  @type ctx :: %{optional(:counter) => non_neg_integer(), optional(:health) => map()}

  @callback order([candidate()], ctx()) :: [candidate()]
end
