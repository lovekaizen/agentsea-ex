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

1. **Core loop** ✅ — Agent GenServer + Provider/Tool/Memory behaviours + Anthropic provider (Req), buffer memory, concurrent + crash-isolated tool execution. (`agentsea_core`, `agentsea_providers`)
2. **Crews** ✅ — capabilities/roles, delegation strategies (round-robin, best-match, auction-as-fan-out), bidding, and a supervised coordinator that runs a task DAG (parallel where possible, dependency-aware) (`agentsea_crews`). Pause/resume/abort + `gen_statem` migration still to come.
3. **Observability** 🚧 — Telemetry instrumentation across provider/agent/tool/crew is done (`AgentSea.Telemetry`); a Phoenix LiveView dashboard consuming the events is next.
4. **Gateway** — Finch pools + `:fuse` + router + OpenAI-compatible endpoint.
5. **Data plane** — Bumblebee embeddings, pgvector memory, Instructor structured output, Broadway ingest/evaluate.
6. **Bridges** — MCP (Hermes/native), surf Node sidecar via Port, voice.

## License

TBD
