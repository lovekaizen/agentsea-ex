# Mock the Provider behaviour so the agent loop can be tested without a network.
Mox.defmock(AgentSea.MockProvider, for: AgentSea.Provider)

ExUnit.start()
