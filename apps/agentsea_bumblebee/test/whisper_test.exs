defmodule AgentSea.Voice.STT.WhisperTest do
  use ExUnit.Case, async: true

  alias AgentSea.Voice
  alias AgentSea.Voice.STT.Whisper

  describe "transcribe/2 plumbing (no model, injected serving)" do
    test "joins Whisper chunk texts" do
      run = fn _serving, _audio ->
        %{chunks: [%{text: " Hello"}, %{text: " world "}]}
      end

      assert {:ok, %{text: "Hello world"}} =
               Whisper.transcribe(<<1, 2, 3>>, serving: :fake, run: run)
    end

    test "tolerates a results-shaped output" do
      run = fn _serving, _audio -> %{results: [%{text: "  transcribed  "}]} end
      assert {:ok, %{text: "transcribed"}} = Whisper.transcribe(<<1>>, serving: :fake, run: run)
    end

    test "tolerates a bare string" do
      run = fn _serving, _audio -> "  bare  " end
      assert {:ok, %{text: "bare"}} = Whisper.transcribe(<<1>>, serving: :fake, run: run)
    end

    test "returns {:error, _} if the serving raises" do
      run = fn _serving, _audio -> raise "decode failed" end
      assert {:error, %RuntimeError{}} = Whisper.transcribe(<<1>>, serving: :fake, run: run)
    end

    test "requires a :serving option" do
      assert_raise KeyError, fn -> Whisper.transcribe(<<1>>, run: fn _, _ -> "x" end) end
    end

    test "works through the Voice.listen facade" do
      run = fn _serving, _audio -> %{chunks: [%{text: "facade ok"}]} end

      assert {:ok, %{text: "facade ok"}} =
               Voice.listen(<<1>>, stt: {Whisper, serving: :fake, run: run})
    end
  end

  test "serving_options/0 reads app env, empty by default" do
    assert Whisper.serving_options() == []

    Application.put_env(:agentsea_bumblebee, :whisper_serving_options,
      defn_options: [compiler: FakeXLA]
    )

    assert Whisper.serving_options() == [defn_options: [compiler: FakeXLA]]
  after
    Application.delete_env(:agentsea_bumblebee, :whisper_serving_options)
  end
end
