Mox.defmock(AgentSea.Embeddings.MockProvider, for: AgentSea.Provider)

# Live pgvector tests need a Postgres with the `vector` extension; excluded by
# default. Run them with: mix test --include postgres
ExUnit.start(exclude: [:postgres])
