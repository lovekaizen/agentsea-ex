defmodule AgentSea.Embedder.HashingTest do
  use ExUnit.Case, async: true

  alias AgentSea.Embedder.Hashing
  alias AgentSea.Vector

  test "produces fixed-dimension, unit-length vectors" do
    {:ok, [v]} = Hashing.embed(["hello world"])
    assert length(v) == Hashing.dimensions()
    assert_in_delta Vector.norm(v), 1.0, 1.0e-9
  end

  test "is deterministic" do
    {:ok, [a]} = Hashing.embed(["the quick brown fox"])
    {:ok, [b]} = Hashing.embed(["the quick brown fox"])
    assert a == b
  end

  test "shared vocabulary is more similar than disjoint vocabulary" do
    {:ok, [cat1]} = Hashing.embed(["the cat sat on the mat"])
    {:ok, [cat2]} = Hashing.embed(["a cat on the mat"])
    {:ok, [finance]} = Hashing.embed(["quarterly revenue grew twelve percent"])

    assert Vector.cosine(cat1, cat2) > Vector.cosine(cat1, finance)
  end

  test "handles the empty string (zero vector)" do
    {:ok, [v]} = Hashing.embed([""])
    assert Vector.norm(v) == 0.0
  end
end
