defmodule AgentSea.Voice.STT.Whisper do
  @moduledoc """
  In-process speech-to-text via Whisper (Bumblebee + Nx) — a local
  `AgentSea.Voice.STT` with no transcription API.

  Build a serving once (it loads the model), then pass it per call:

      serving = AgentSea.Voice.STT.Whisper.serving("openai/whisper-tiny")
      {:ok, %{text: text}} = AgentSea.Voice.STT.Whisper.transcribe(audio, serving: serving)

  The serving accepts what Bumblebee's Whisper serving accepts (raw PCM samples
  as an `Nx.Tensor`, or a file path when `ffmpeg` is available). The serving call
  is injectable (`:run`) so the transcription plumbing is testable without a
  model. Add `:exla` for real throughput (see `AgentSea.Embedder.Bumblebee`).
  """

  @behaviour AgentSea.Voice.STT

  @default_model "openai/whisper-tiny"

  @doc "Build an `Nx.Serving` for a Whisper model. Downloads the model on first use."
  def serving(model_id \\ @default_model, opts \\ []) do
    {:ok, whisper} = Bumblebee.load_model({:hf, model_id})
    {:ok, featurizer} = Bumblebee.load_featurizer({:hf, model_id})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, model_id})
    {:ok, generation_config} = Bumblebee.load_generation_config({:hf, model_id})

    Bumblebee.Audio.speech_to_text_whisper(
      whisper,
      featurizer,
      tokenizer,
      generation_config,
      Keyword.merge(serving_options(), opts)
    )
  end

  @doc "Serving options from app config (e.g. an EXLA compiler), overridable per call."
  def serving_options do
    Application.get_env(:agentsea_bumblebee, :whisper_serving_options, [])
  end

  @impl true
  def transcribe(audio, opts) do
    serving = Keyword.fetch!(opts, :serving)
    run = Keyword.get(opts, :run, &Nx.Serving.run/2)

    try do
      text = serving |> run.(audio) |> to_text()
      {:ok, %{text: text}}
    rescue
      error -> {:error, error}
    end
  end

  # Whisper servings yield %{chunks: [%{text: ...}]}; chunk texts carry their own
  # leading spaces, so concatenate directly. Tolerate a couple of other shapes.
  defp to_text(%{chunks: chunks}) when is_list(chunks) do
    chunks |> Enum.map_join("", & &1.text) |> String.trim()
  end

  defp to_text(%{results: [%{text: text} | _]}), do: String.trim(text)
  defp to_text(text) when is_binary(text), do: String.trim(text)
end
