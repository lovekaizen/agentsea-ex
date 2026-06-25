# AgentSea (Elixir)

An idiomatic Elixir/OTP rewrite of the [AgentSea](https://github.com/lovekaizen/agentsea) agentic ADK — **not** a port of the TypeScript SDK.

> **Status: design complete.** All six phases are implemented and tested — 13 umbrella apps, 138 tests green (plus opt-in live integration tests for Postgres and Bumblebee). See [docs/DESIGN.md](docs/DESIGN.md) for the original plan.

## Thesis

A multi-agent framework where agents are supervised processes, delegation is message passing, the auction is a timed `GenServer` fan-out, failover is a restart strategy, and you watch the whole fleet execute live in LiveView.

Where OTP already solves it, we delete the abstraction and use the primitive. We keep AgentSea's *concepts* (Agent, Provider, Tool, Memory, Crew, Role, Capability, delegation strategy, Gateway, evaluation) and discard the TypeScript *shapes*.

## Getting started

```bash
asdf install     # Erlang/OTP 25 + Elixir 1.18 (see .tool-versions)
mix deps.get
mix test         # the default suite — no external services needed
```

Everything in the default suite runs offline: providers are stubbed via `Req` adapters, LLM behaviours via Mox, and the MCP/surf sidecars run real subprocesses (`awk`, `node`) that speak the wire protocol without a model or network.

## Architecture

An umbrella of independently-releasable `agentsea_*` apps. Each owns one concern and depends only on what it needs; behaviours (not inheritance) are the seams between them.

| App | Concern |
|-----|---------|
| `agentsea_core` | Agent `GenServer` + the run loop; `Provider`/`Tool`/`Memory`/`Tool.Spec` behaviours; capabilities, roles, bidding; `:telemetry` spans; buffer memory; crash-isolated concurrent tool execution |
| `agentsea_providers` | Anthropic provider over `Req` — `complete/2` and real SSE `stream/2`; an SSE framer |
| `agentsea_crews` | `DynamicSupervisor` + `Registry`; delegation strategies (round-robin, best-match, auction-as-fan-out); a coordinator that runs a task DAG, dependency-aware and parallel where possible |
| `agentsea_gateway` | strategy routing (failover, round-robin, cost-/latency-optimized); `:fuse` circuit breaking; per-provider health; non-streaming and streaming routing |
| `agentsea_web` | Phoenix LiveView fleet dashboard fed by telemetry + PubSub; OpenAI-compatible `POST /v1/chat/completions` with real token streaming |
| `agentsea_structured` | Ecto-changeset structured extraction with validation-retry |
| `agentsea_embeddings` | `Embedder`/`VectorStore` behaviours; hashing + **OpenAI/Cohere** embedders; in-memory, **pgvector**, **Qdrant**, **Pinecone** stores; a RAG retrieval tool |
| `agentsea_bumblebee` | in-process HF-model embedder **and Whisper STT** via Bumblebee + Nx (no API) |
| `agentsea_ingest` | Broadway pipeline: chunk → embed → store, with batching/backpressure |
| `agentsea_evaluate` | concurrent metrics (exact-match, contains, LLM-as-judge) + aggregation |
| `agentsea_guardrails` | input/output guardrail pipeline — max-length, blocklist, PII redaction, LLM moderation |
| `agentsea_mcp` | MCP client with **stdio** and **streamable-HTTP** transports; server tools adapted into agent `Tool.Spec`s |
| `agentsea_surf` | Node/Playwright browser sidecar over a `Port`, exposed as agent tools |
| `agentsea_voice` | `TTS`/`STT` behaviours + OpenAI (TTS+STT) and ElevenLabs (TTS) adapters over `Req` |

## Roadmap (all delivered)

1. **Core loop** ✅ — agent GenServer, behaviours, Anthropic provider (`complete` + streaming), buffer memory, concurrent crash-isolated tools.
2. **Crews** ✅ — capabilities/roles, delegation strategies, bidding, a supervised coordinator running a task DAG.
3. **Observability** ✅ — telemetry across provider/agent/tool/crew + a live LiveView dashboard.
4. **Gateway** ✅ — routing strategies, `:fuse` circuit breaking, failover, health, and an OpenAI-compatible streaming endpoint.
5. **Data plane** ✅ — structured output, embeddings/RAG (in-memory + pgvector + Bumblebee), Broadway ingestion, evaluation.
6. **Bridges** ✅ — MCP (stdio + HTTP), surf Node sidecar, voice.

Future refinements (beyond the original scope): crew pause/resume/abort + `gen_statem`, an `:exla` backend for Bumblebee, ElevenLabs/local voice adapters.

## Testing

```bash
mix test                          # default: offline, no external services
mix test --include postgres       # + live pgvector (needs Postgres w/ the vector extension)
mix test --include bumblebee      # + live HF model (downloads all-MiniLM-L6-v2, ~90MB)
mix format --check-formatted
mix compile --warnings-as-errors
mix credo                         # static analysis
mix dialyzer                      # type analysis (first run builds the PLT)
mix docs                          # aggregated HTML docs across all apps -> doc/
```

Heavyweight or service-dependent tests are tagged and **excluded by default**, so the standard suite stays fast and hermetic; CI runs that suite plus the format, warnings-as-errors, Credo, and Dialyzer gates.

## License

TBD
