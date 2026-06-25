defmodule AgentSea.Voice.OpenAI do
  @moduledoc """
  OpenAI voice adapter: text-to-speech (`/v1/audio/speech`) and speech-to-text
  (`/v1/audio/transcriptions`) over `Req`.

  Options: `:api_key` (defaults to `OPENAI_API_KEY`), `:model`, `:voice`,
  `:format`, `:base_url`, and `:adapter` (a Req adapter, used to stub HTTP in
  tests).
  """

  @behaviour AgentSea.Voice.TTS
  @behaviour AgentSea.Voice.STT

  @base_url "https://api.openai.com"

  @impl AgentSea.Voice.TTS
  def synthesize(text, opts) do
    body = %{
      model: opts[:model] || "tts-1",
      input: text,
      voice: opts[:voice] || "alloy",
      response_format: opts[:format] || "mp3"
    }

    case Req.post(req(opts), url: "/v1/audio/speech", json: body) do
      {:ok, %Req.Response{status: 200, body: audio}} when is_binary(audio) ->
        {:ok, %{audio: audio, format: opts[:format] || "mp3"}}

      {:ok, %Req.Response{status: status, body: resp}} ->
        {:error, {:http_error, status, resp}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl AgentSea.Voice.STT
  def transcribe(audio, opts) do
    multipart = [
      model: opts[:model] || "whisper-1",
      file: {audio, filename: "audio.mp3", content_type: "audio/mpeg"}
    ]

    case Req.post(req(opts), url: "/v1/audio/transcriptions", form_multipart: multipart) do
      {:ok, %Req.Response{status: 200, body: %{"text" => text}}} ->
        {:ok, %{text: text}}

      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        decode_text(body)

      {:ok, %Req.Response{status: status, body: resp}} ->
        {:error, {:http_error, status, resp}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp req(opts) do
    api_key = opts[:api_key] || System.get_env("OPENAI_API_KEY")

    [
      base_url: opts[:base_url] || @base_url,
      headers: [{"authorization", "Bearer #{api_key || ""}"}]
    ]
    |> maybe_put(:adapter, opts[:adapter])
    |> Req.new()
  end

  defp maybe_put(kw, _key, nil), do: kw
  defp maybe_put(kw, key, value), do: Keyword.put(kw, key, value)

  defp decode_text(body) do
    case Jason.decode(body) do
      {:ok, %{"text" => text}} -> {:ok, %{text: text}}
      _ -> {:error, :invalid_response}
    end
  end
end
