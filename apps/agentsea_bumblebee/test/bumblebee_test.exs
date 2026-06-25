defmodule AgentSea.Embedder.BumblebeeTest do
  use ExUnit.Case, async: true

  alias AgentSea.Embedder.Bumblebee, as: Embedder

  describe "embed/2 plumbing (no model, injected serving)" do
    test "maps each text through the serving and returns float vectors" do
      # Fake serving: echoes a deterministic tensor per text length.
      run = fn _serving, text -> %{embedding: Nx.tensor([1.0, 2.0, byte_size(text) / 1])} end

      assert {:ok, vectors} = Embedder.embed(["hi", "yes"], serving: :fake, run: run)
      assert vectors == [[1.0, 2.0, 2.0], [1.0, 2.0, 3.0]]
    end

    test "tolerates a bare tensor result" do
      run = fn _serving, _text -> Nx.tensor([0.5, -0.5]) end
      assert {:ok, [[0.5, -0.5]]} = Embedder.embed(["x"], serving: :fake, run: run)
    end

    test "optionally L2-normalizes" do
      run = fn _serving, _text -> %{embedding: Nx.tensor([3.0, 4.0])} end

      assert {:ok, [vector]} = Embedder.embed(["x"], serving: :fake, run: run, normalize: true)
      assert_in_delta Enum.sum(Enum.map(vector, &(&1 * &1))), 1.0, 1.0e-9
      assert_in_delta Enum.at(vector, 0), 0.6, 1.0e-9
    end

    test "returns {:error, _} if the serving raises" do
      run = fn _serving, _text -> raise "model exploded" end
      assert {:error, %RuntimeError{}} = Embedder.embed(["x"], serving: :fake, run: run)
    end

    test "requires a :serving option" do
      assert_raise KeyError, fn -> Embedder.embed(["x"], run: fn _, _ -> Nx.tensor([1]) end) end
    end
  end

  test "serving_options/0 reads app env (for EXLA etc.), empty by default" do
    assert Embedder.serving_options() == []

    Application.put_env(:agentsea_bumblebee, :serving_options, defn_options: [compiler: FakeXLA])
    assert Embedder.serving_options() == [defn_options: [compiler: FakeXLA]]
  after
    Application.delete_env(:agentsea_bumblebee, :serving_options)
  end

  test "dimensions/0 reads app env (default 384)" do
    assert Embedder.dimensions() == 384

    Application.put_env(:agentsea_bumblebee, :dimensions, 768)
    assert Embedder.dimensions() == 768
  after
    Application.delete_env(:agentsea_bumblebee, :dimensions)
  end

  # Live model test — downloads all-MiniLM-L6-v2. Excluded by default.
  # Run with: mix test --include bumblebee
  @tag :bumblebee
  @tag timeout: 600_000
  test "embeds real text with a Hugging Face model" do
    serving = Embedder.serving()

    assert {:ok, [v1, v2, v3]} =
             Embedder.embed(
               ["a cat sat on the mat", "a feline rested on the rug", "stock market crash"],
               serving: serving,
               normalize: true
             )

    assert length(v1) == 384

    cosine = fn a, b -> Enum.zip(a, b) |> Enum.map(fn {x, y} -> x * y end) |> Enum.sum() end
    # Paraphrases should be closer than unrelated text.
    assert cosine.(v1, v2) > cosine.(v1, v3)
  end
end
