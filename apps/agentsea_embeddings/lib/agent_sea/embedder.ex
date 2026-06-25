defmodule AgentSea.Embedder do
  @moduledoc """
  Turns text into vectors. Adapters: the dependency-free
  `AgentSea.Embedder.Hashing` (good for tests/dev) and, in future, Bumblebee/Nx
  (in-process HF/ONNX models) or remote embedding providers.
  """

  @callback embed(texts :: [String.t()], opts :: keyword()) ::
              {:ok, [[float()]]} | {:error, term()}

  @callback dimensions() :: pos_integer()
end
