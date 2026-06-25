# AgentSea (Elixir)

An idiomatic Elixir/OTP rewrite of the [AgentSea](https://github.com/lovekaizen/agentsea) agentic ADK — **not** a port of the TypeScript SDK.

> **Status: Phase 1 in progress.** The core loop is implemented and tested — see [docs/DESIGN.md](docs/DESIGN.md) for the full plan.

## Getting started

```bash
asdf install            # Erlang/OTP 25 + Elixir 1.18 (see .tool-versions)
mix deps.get
mix test
```

## Thesis

A multi-agent framework where agents are supervised processes, delegation is message passing, the auction is a timed `GenServer` fan-out, failover is a restart strategy, and you watch the whole fleet execute live in LiveView.

Where OTP already solves it, we delete the abstraction and use the primitive. We keep AgentSea's *concepts* (Agent, Provider, Tool, Memory, Crew, Role, Capability, delegation strategy, Gateway, evaluation) and discard the TypeScript *shapes*.

## Layout (planned)

An umbrella of independently-releasable `agentsea_*` apps (`core`, `providers`, `crews`, `gateway`, `memory`, `embeddings`, `structured`, `ingest`, `evaluate`, `mcp`, `guardrails`, `surf`, `web`). See [docs/DESIGN.md](docs/DESIGN.md).

## Roadmap

1. **Core loop** ✅ — Agent GenServer + Provider/Tool/Memory behaviours + Anthropic provider (Req) with non-streaming `complete/2` **and** real SSE `stream/2`, buffer memory, concurrent + crash-isolated tool execution. (`agentsea_core`, `agentsea_providers`)
2. **Crews** ✅ — capabilities/roles, delegation strategies (round-robin, best-match, auction-as-fan-out), bidding, and a supervised coordinator that runs a task DAG (parallel where possible, dependency-aware) (`agentsea_crews`). Pause/resume/abort + `gen_statem` migration still to come.
3. **Observability** ✅ — Telemetry instrumentation across provider/agent/tool/crew (`AgentSea.Telemetry`) plus a Phoenix LiveView dashboard (`agentsea_web`) that renders live fleet activity from those events.
4. **Gateway** ✅ — strategy-based routing (failover, round-robin, cost-, latency-optimized), `:fuse` circuit breaking, failover, and health tracking (`agentsea_gateway`), plus an OpenAI-compatible `POST /v1/chat/completions` endpoint with **real token streaming** — provider `stream/2` events forwarded straight through as SSE chunks (`agentsea_web`).
5. **Data plane** 🚧 — Ecto-changeset structured output (`agentsea_structured`); an embeddings/vector-search stack with a RAG retrieval tool (`agentsea_embeddings`); a Broadway document ingestion pipeline (`agentsea_ingest`); and concurrent evaluation with exact-match/contains/LLM-as-judge metrics + aggregation (`agentsea_evaluate`). Bumblebee/pgvector adapters next.
6. **Bridges** 🚧 — an MCP client + stdio transport (`agentsea_mcp`) and a surf Node sidecar — a supervised `Port` to a Node/Playwright subprocess (newline-JSON, id-correlated), with browser actions exposed as agent tools (`agentsea_surf`) — are done; a streamable-HTTP MCP transport and voice next.

## License

TBD
