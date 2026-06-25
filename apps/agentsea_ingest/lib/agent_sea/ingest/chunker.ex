defmodule AgentSea.Ingest.Chunker do
  @moduledoc """
  Splits text into overlapping word windows. Overlap preserves context across
  chunk boundaries (so a fact split between two chunks still embeds coherently
  in at least one).
  """

  @default_size 120
  @default_overlap 20

  @doc """
  Chunk `text` into word windows.

  Options: `:size` (words per chunk, default #{@default_size}) and `:overlap`
  (words shared with the previous chunk, default #{@default_overlap}).
  """
  @spec chunk(String.t(), keyword()) :: [String.t()]
  def chunk(text, opts \\ []) do
    size = Keyword.get(opts, :size, @default_size)
    overlap = Keyword.get(opts, :overlap, @default_overlap)
    step = max(size - overlap, 1)

    text
    |> String.split(~r/\s+/u, trim: true)
    |> windows(size, step, [])
  end

  defp windows([], _size, _step, acc), do: Enum.reverse(acc)

  defp windows(words, size, step, acc) do
    chunk = words |> Enum.take(size) |> Enum.join(" ")
    acc = [chunk | acc]

    if length(words) <= size do
      Enum.reverse(acc)
    else
      windows(Enum.drop(words, step), size, step, acc)
    end
  end
end
