defmodule AgentSea.Voice do
  @moduledoc """
  Voice facade over pluggable TTS/STT adapters.

  ## Example

      {:ok, %{audio: mp3}} =
        AgentSea.Voice.speak("Hello!", tts: {AgentSea.Voice.OpenAI, voice: "nova"})

      {:ok, %{text: text}} =
        AgentSea.Voice.listen(mp3, stt: {AgentSea.Voice.OpenAI, []})
  """

  @doc "Synthesize speech. `:tts` is `{module, opts}` (a `AgentSea.Voice.TTS`)."
  @spec speak(String.t(), keyword()) :: {:ok, AgentSea.Voice.TTS.result()} | {:error, term()}
  def speak(text, opts) do
    {module, adapter_opts} = Keyword.fetch!(opts, :tts)
    module.synthesize(text, adapter_opts)
  end

  @doc "Transcribe audio. `:stt` is `{module, opts}` (a `AgentSea.Voice.STT`)."
  @spec listen(binary(), keyword()) :: {:ok, AgentSea.Voice.STT.result()} | {:error, term()}
  def listen(audio, opts) do
    {module, adapter_opts} = Keyword.fetch!(opts, :stt)
    module.transcribe(audio, adapter_opts)
  end
end
