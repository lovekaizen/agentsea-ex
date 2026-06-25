defmodule AgentSea.VectorStore.PostgresTest do
  use ExUnit.Case, async: true

  alias AgentSea.VectorStore.Postgres

  describe "pure helpers (always run)" do
    test "vector_literal encodes a pgvector text literal" do
      assert Postgres.vector_literal([1.0, 2.5, -3.0]) == "[1.0,2.5,-3.0]"
      assert Postgres.vector_literal([]) == "[]"
    end

    test "valid_table! accepts identifiers and rejects injection" do
      assert Postgres.valid_table!("embeddings") == "embeddings"
      assert Postgres.valid_table!("agentsea_v2") == "agentsea_v2"

      assert_raise ArgumentError, fn -> Postgres.valid_table!("a; drop table x") end
      assert_raise ArgumentError, fn -> Postgres.valid_table!("1bad") end
    end

    test "store/2 validates the table and requires dimensions" do
      store = Postgres.store(:fake_conn, table: "vecs", dimensions: 8)
      assert store == %{conn: :fake_conn, table: "vecs", dimensions: 8}

      assert_raise KeyError, fn -> Postgres.store(:fake_conn, table: "vecs") end

      assert_raise ArgumentError, fn ->
        Postgres.store(:fake_conn, table: "bad name", dimensions: 8)
      end
    end

    test "implements the AgentSea.VectorStore callbacks" do
      # (@behaviour + @impl already enforce this at compile time.)
      # ensure_loaded! so function_exported?/3 doesn't see an unloaded module
      # when this test happens to run before the others (ordering is seeded).
      Code.ensure_loaded!(Postgres)
      assert function_exported?(Postgres, :upsert, 2)
      assert function_exported?(Postgres, :query, 4)
      assert function_exported?(Postgres, :delete, 2)
      assert function_exported?(Postgres, :count, 1)
    end
  end

  # Live integration against a real Postgres + pgvector. Excluded by default
  # (see test_helper). Run with: mix test --include postgres
  describe "live pgvector" do
    @describetag :postgres

    alias AgentSea.Embeddings
    alias AgentSea.Embedder.Hashing

    setup do
      opts = [
        hostname: System.get_env("PGHOST", "localhost"),
        username: System.get_env("PGUSER", "postgres"),
        password: System.get_env("PGPASSWORD", "postgres"),
        database: System.get_env("PGDATABASE", "agentsea_test")
      ]

      {:ok, conn} = Postgrex.start_link(opts)
      table = "vt_#{System.unique_integer([:positive])}"
      store = Postgres.store(conn, table: table, dimensions: Hashing.dimensions())
      :ok = Postgres.ensure_table(store)

      on_exit(fn -> Postgrex.query(conn, "DROP TABLE IF EXISTS #{table}", []) end)
      {:ok, store: store}
    end

    test "upsert, count, delete", %{store: store} do
      {:ok, [v1, v2]} = Hashing.embed(["alpha", "beta"])
      :ok = Postgres.upsert(store, [%{id: "a", vector: v1}, %{id: "b", vector: v2}])
      assert Postgres.count(store) == 2

      :ok = Postgres.delete(store, ["a"])
      assert Postgres.count(store) == 1
    end

    test "index + semantic search via the Embeddings facade", %{store: store} do
      handle = Embeddings.new(store_mod: Postgres, store: store, embedder: Hashing)

      Embeddings.index(handle, [
        %{id: "refund", text: "refund policy allows returns within thirty days"},
        %{id: "hours", text: "store opening hours are weekdays only"}
      ])

      assert [top | _] = Embeddings.search(handle, "refund policy", 2)
      assert top.id == "refund"
      assert top.score > 0.0
    end

    test "metadata jsonb filter", %{store: store} do
      {:ok, [v]} = Hashing.embed(["x"])

      Postgres.upsert(store, [
        %{id: "en", vector: v, metadata: %{"lang" => "en"}},
        %{id: "fr", vector: v, metadata: %{"lang" => "fr"}}
      ])

      hits = Postgres.query(store, v, 5, where: %{"lang" => "fr"})
      assert Enum.map(hits, & &1.id) == ["fr"]
    end
  end
end
