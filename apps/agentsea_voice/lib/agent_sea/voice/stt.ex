defmodule AgentSea.Voice.STT do
  @moduledoc """
  Speech-to-text behaviour. Adapters: remote (OpenAI Whisper over Req) or, in
  future, local (Whisper via Bumblebee, in-process).
  """

  @type result :: %{text: String.t()}

  @callback transcribe(audio :: binary(), opts :: keyword()) ::
              {:ok, result()} | {:error, term()}
end
