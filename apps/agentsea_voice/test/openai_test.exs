defmodule AgentSea.Voice.OpenAITest do
  use ExUnit.Case, async: true

  alias AgentSea.Voice
  alias AgentSea.Voice.OpenAI

  # A Req adapter returning a fixed response (optionally asserting the request).
  defp adapter(body, status \\ 200, assert_fn \\ nil) do
    fn request ->
      if assert_fn, do: assert_fn.(request)
      {request, Req.Response.new(status: status, body: body)}
    end
  end

  defp opts(adapter), do: [api_key: "test", adapter: adapter]

  describe "synthesize (TTS)" do
    test "returns the audio bytes and format" do
      audio = <<0, 1, 2, 3, 4>>
      a = adapter(audio)

      assert {:ok, %{audio: ^audio, format: "mp3"}} =
               OpenAI.synthesize("Hello there", opts(a))
    end

    test "sends the input text, voice and model" do
      assert_request = fn request ->
        body = decode(request.body)
        assert body["input"] == "Hi"
        assert body["voice"] == "nova"
        assert body["model"] == "tts-1"
      end

      a = adapter(<<9>>, 200, assert_request)
      assert {:ok, %{audio: <<9>>}} = OpenAI.synthesize("Hi", opts(a) ++ [voice: "nova"])
    end

    test "surfaces a non-200 as an error" do
      a = adapter(%{"error" => %{"message" => "bad"}}, 401)
      assert {:error, {:http_error, 401, _}} = OpenAI.synthesize("Hi", opts(a))
    end
  end

  describe "transcribe (STT)" do
    test "returns the transcribed text" do
      a = adapter(%{"text" => "hello world"})
      assert {:ok, %{text: "hello world"}} = OpenAI.transcribe(<<1, 2, 3>>, opts(a))
    end

    test "decodes a JSON string body" do
      a = adapter(~s({"text":"from json"}))
      assert {:ok, %{text: "from json"}} = OpenAI.transcribe(<<1>>, opts(a))
    end

    test "surfaces a non-200 as an error" do
      a = adapter(%{"error" => "nope"}, 500)
      assert {:error, {:http_error, 500, _}} = OpenAI.transcribe(<<1>>, opts(a))
    end
  end

  describe "facade" do
    test "speak/2 and listen/2 dispatch to the adapter" do
      tts = adapter(<<7, 7>>)
      stt = adapter(%{"text" => "round trip"})

      assert {:ok, %{audio: <<7, 7>>}} =
               Voice.speak("hi", tts: {OpenAI, api_key: "k", adapter: tts})

      assert {:ok, %{text: "round trip"}} =
               Voice.listen(<<1>>, stt: {OpenAI, api_key: "k", adapter: stt})
    end
  end

  defp decode(body) when is_map(body), do: body
  defp decode(body), do: body |> IO.iodata_to_binary() |> Jason.decode!()
end
