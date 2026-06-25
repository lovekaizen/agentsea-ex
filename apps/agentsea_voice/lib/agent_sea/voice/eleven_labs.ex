defmodule AgentSea.Voice.ElevenLabs do
  @moduledoc """
  ElevenLabs text-to-speech adapter (`POST /v1/text-to-speech/:voice_id`) over
  `Req`. Implements `AgentSea.Voice.TTS`.

  Options: `:api_key` (defaults to `ELEVENLABS_API_KEY`), `:voice` (voice id),
  `:model`, `:base_url`, and `:adapter` (a Req adapter, to stub HTTP in tests).
  """

  @behaviour AgentSea.Voice.TTS

  @base_url "https://api.elevenlabs.io"
  # "Rachel" — ElevenLabs' default sample voice.
  @default_voice "21m00Tcm4TlvDq8ikWAM"

  @impl true
  def synthesize(text, opts) do
    voice = opts[:voice] || @default_voice
    body = %{text: text, model_id: opts[:model] || "eleven_multilingual_v2"}

    case Req.post(req(opts), url: "/v1/text-to-speech/#{voice}", json: body) do
      {:ok, %Req.Response{status: 200, body: audio}} when is_binary(audio) ->
        {:ok, %{audio: audio, format: "mp3"}}

      {:ok, %Req.Response{status: status, body: resp}} ->
        {:error, {:http_error, status, resp}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp req(opts) do
    api_key = opts[:api_key] || System.get_env("ELEVENLABS_API_KEY")

    [
      base_url: opts[:base_url] || @base_url,
      headers: [{"xi-api-key", api_key || ""}]
    ]
    |> maybe_put(:adapter, opts[:adapter])
    |> Req.new()
  end

  defp maybe_put(kw, _key, nil), do: kw
  defp maybe_put(kw, key, value), do: Keyword.put(kw, key, value)
end
