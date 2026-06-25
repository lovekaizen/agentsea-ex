defmodule AgentSea.Embedder.Bumblebee do
  @moduledoc """
  In-process text embedder backed by a Hugging Face model via Bumblebee + Nx —
  the production `AgentSea.Embedder` (no external embedding API).

  Build a serving once (it loads the model), then pass it on each call:

      serving = AgentSea.Embedder.Bumblebee.serving("sentence-transformers/all-MiniLM-L6-v2")
      {:ok, vectors} = AgentSea.Embedder.Bumblebee.embed(["hello", "world"], serving: serving)

  Runs on Nx's pure-Elixir backend out of the box; add `:exla` for speed. The
  serving call is injectable (`:run`) so the embedding plumbing is testable
  without loading a model.
  """

  @behaviour AgentSea.Embedder

  @default_model "sentence-transformers/all-MiniLM-L6-v2"

  @doc """
  Build an `Nx.Serving` for a text-embedding model. Downloads the model on first
  use (network), so this is a runtime/setup call, not used in unit tests.
  """
  def serving(model_id \\ @default_model, opts \\ []) do
    {:ok, model} = Bumblebee.load_model({:hf, model_id})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, model_id})
    Bumblebee.Text.text_embedding(model, tokenizer, opts)
  end

  @impl true
  def embed(texts, opts) when is_list(texts) do
    serving = Keyword.fetch!(opts, :serving)
    run = Keyword.get(opts, :run, &Nx.Serving.run/2)
    normalize? = Keyword.get(opts, :normalize, false)

    # Only inference failures become {:error, _}; a missing :serving is a
    # programmer error and raises above.
    try do
      vectors =
        Enum.map(texts, fn text ->
          serving
          |> run.(text)
          |> to_vector()
          |> maybe_normalize(normalize?)
        end)

      {:ok, vectors}
    rescue
      error -> {:error, error}
    end
  end

  @impl true
  def dimensions do
    Application.get_env(:agentsea_bumblebee, :dimensions, 384)
  end

  # A text-embedding serving yields %{embedding: tensor}; tolerate a bare tensor.
  defp to_vector(%{embedding: tensor}), do: Nx.to_flat_list(tensor)
  defp to_vector(tensor), do: Nx.to_flat_list(tensor)

  defp maybe_normalize(vector, false), do: vector
  defp maybe_normalize(vector, true), do: AgentSea.Vector.normalize(vector)
end
