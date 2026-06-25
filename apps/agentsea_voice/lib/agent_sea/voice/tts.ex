defmodule AgentSea.Voice.TTS do
  @moduledoc """
  Text-to-speech behaviour. Adapters: remote (OpenAI/ElevenLabs over Req) or, in
  future, local (Piper / Bumblebee).
  """

  @type result :: %{audio: binary(), format: String.t()}

  @callback synthesize(text :: String.t(), opts :: keyword()) ::
              {:ok, result()} | {:error, term()}
end
