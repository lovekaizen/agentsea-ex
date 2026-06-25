defmodule AgentSea.Vector do
  @moduledoc "Small vector math: dot product, L2 norm, normalization, cosine similarity."

  @type t :: [float()]

  @spec dot(t(), t()) :: float()
  def dot(a, b) do
    a |> Enum.zip(b) |> Enum.reduce(0.0, fn {x, y}, acc -> acc + x * y end)
  end

  @spec norm(t()) :: float()
  def norm(vec), do: :math.sqrt(Enum.reduce(vec, 0.0, fn x, acc -> acc + x * x end))

  @doc "Scale a vector to unit length (returns it unchanged if it's the zero vector)."
  @spec normalize(t()) :: t()
  def normalize(vec) do
    n = norm(vec)
    if n == 0.0, do: vec, else: Enum.map(vec, &(&1 / n))
  end

  @doc "Cosine similarity in [-1, 1] (0.0 if either vector is zero)."
  @spec cosine(t(), t()) :: float()
  def cosine(a, b) do
    na = norm(a)
    nb = norm(b)
    if na == 0.0 or nb == 0.0, do: 0.0, else: dot(a, b) / (na * nb)
  end
end
