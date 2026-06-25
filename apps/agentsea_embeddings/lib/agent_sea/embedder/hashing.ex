defmodule AgentSea.Embedder.Hashing do
  @moduledoc """
  A deterministic, dependency-free embedder using the hashing trick: tokens are
  hashed into fixed-dimension buckets (bag-of-words), then the vector is L2
  normalized. Texts that share words land closer together — enough for tests,
  local dev, and demos without pulling in an ML runtime.
  """

  @behaviour AgentSea.Embedder

  @dimensions 64

  @impl true
  def dimensions, do: @dimensions

  @impl true
  def embed(texts, _opts \\ []) when is_list(texts) do
    {:ok, Enum.map(texts, &vectorize/1)}
  end

  defp vectorize(text) do
    counts =
      text
      |> tokens()
      |> Enum.reduce(%{}, fn token, acc ->
        bucket = :erlang.phash2(token, @dimensions)
        Map.update(acc, bucket, 1.0, &(&1 + 1.0))
      end)

    vec = for i <- 0..(@dimensions - 1), do: Map.get(counts, i, 0.0)
    AgentSea.Vector.normalize(vec)
  end

  defp tokens(text) do
    text
    |> String.downcase()
    |> String.split(~r/\W+/u, trim: true)
  end
end
