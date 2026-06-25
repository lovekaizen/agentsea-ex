defmodule AgentSea.Voice.ElevenLabsTest do
  use ExUnit.Case, async: true

  alias AgentSea.Voice
  alias AgentSea.Voice.ElevenLabs

  defp adapter(body, status \\ 200, assert_fn \\ nil) do
    fn request ->
      if assert_fn, do: assert_fn.(request)
      {request, Req.Response.new(status: status, body: body)}
    end
  end

  test "synthesize returns audio bytes" do
    audio = <<10, 20, 30>>

    assert {:ok, %{audio: ^audio, format: "mp3"}} =
             ElevenLabs.synthesize("Hello", api_key: "k", adapter: adapter(audio))
  end

  test "posts to the voice-specific endpoint with the text" do
    assert_request = fn request ->
      assert request.url.path == "/v1/text-to-speech/my-voice"
      assert Jason.decode!(IO.iodata_to_binary(request.body))["text"] == "Read this"
      assert Req.Request.get_header(request, "xi-api-key") == ["secret"]
    end

    a = adapter(<<1>>, 200, assert_request)

    assert {:ok, %{audio: <<1>>}} =
             ElevenLabs.synthesize("Read this", api_key: "secret", voice: "my-voice", adapter: a)
  end

  test "surfaces a non-200 as an error" do
    a = adapter(%{"detail" => "bad voice"}, 422)
    assert {:error, {:http_error, 422, _}} = ElevenLabs.synthesize("x", api_key: "k", adapter: a)
  end

  test "works through the Voice facade" do
    a = adapter(<<7, 7, 7>>)

    assert {:ok, %{audio: <<7, 7, 7>>}} =
             Voice.speak("hi", tts: {ElevenLabs, api_key: "k", adapter: a})
  end
end
