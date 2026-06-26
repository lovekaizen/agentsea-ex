# AgentSea (Elixir)

[![CI](https://github.com/lovekaizen/agentsea-ex/actions/workflows/ci.yml/badge.svg)](https://github.com/lovekaizen/agentsea-ex/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/agentsea_core.svg?label=agentsea_core)](https://hex.pm/packages/agentsea_core)
[![Docs](https://img.shields.io/badge/hexdocs-online-8e7eff.svg)](https://hexdocs.pm/agentsea_core)
[![Elixir](https://img.shields.io/badge/elixir-~%3E%201.14-purple.svg)](https://elixir-lang.org)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

An idiomatic Elixir/OTP rewrite of the [AgentSea](https://github.com/lovekaizen/agentsea) agentic ADK.

All 14 apps are published on Hex — each is its own package. The table below links every app to its HexDocs and shows its current Hex version.

> **Status: design complete.** All six phases are implemented and tested — 14 umbrella apps, 138 tests green (plus opt-in live integration tests for Postgres and Bumblebee). See [docs/DESIGN.md](docs/DESIGN.md) for the original plan.

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

| Package | Hex | Concern |
|---------|-----|---------|
| [`agentsea_core`](https://hexdocs.pm/agentsea_core) | [![Hex](https://img.shields.io/hexpm/v/agentsea_core.svg)](https://hex.pm/packages/agentsea_core) | Agent `GenServer` + the run loop (with optional guardrail hooks); `Provider`/`Tool`/`Memory`/`Tool.Spec` behaviours; capabilities, roles, bidding; `:telemetry` spans; buffer + LLM-summary memory; crash-isolated concurrent tool execution |
| [`agentsea_providers`](https://hexdocs.pm/agentsea_providers) | [![Hex](https://img.shields.io/hexpm/v/agentsea_providers.svg)](https://hex.pm/packages/agentsea_providers) | Anthropic provider over `Req` — `complete/2` and real SSE `stream/2`; an SSE framer |
| [`agentsea_crews`](https://hexdocs.pm/agentsea_crews) | [![Hex](https://img.shields.io/hexpm/v/agentsea_crews.svg)](https://hex.pm/packages/agentsea_crews) | `DynamicSupervisor` + `Registry`; delegation strategies (round-robin, best-match, auction-as-fan-out); a coordinator that runs a task DAG, dependency-aware and parallel where possible |
| [`agentsea_gateway`](https://hexdocs.pm/agentsea_gateway) | [![Hex](https://img.shields.io/hexpm/v/agentsea_gateway.svg)](https://hex.pm/packages/agentsea_gateway) | strategy routing (failover, round-robin, cost-/latency-optimized); `:fuse` circuit breaking; per-provider health; non-streaming and streaming routing |
| [`agentsea_web`](https://hexdocs.pm/agentsea_web) | [![Hex](https://img.shields.io/hexpm/v/agentsea_web.svg)](https://hex.pm/packages/agentsea_web) | Phoenix LiveView fleet dashboard fed by telemetry + PubSub; OpenAI-compatible `POST /v1/chat/completions` with real token streaming |
| [`agentsea_structured`](https://hexdocs.pm/agentsea_structured) | [![Hex](https://img.shields.io/hexpm/v/agentsea_structured.svg)](https://hex.pm/packages/agentsea_structured) | Ecto-changeset structured extraction with validation-retry |
| [`agentsea_embeddings`](https://hexdocs.pm/agentsea_embeddings) | [![Hex](https://img.shields.io/hexpm/v/agentsea_embeddings.svg)](https://hex.pm/packages/agentsea_embeddings) | `Embedder`/`VectorStore` behaviours; hashing + **OpenAI/Cohere** embedders; in-memory, **pgvector**, **Qdrant**, **Pinecone** stores; a RAG retrieval tool; **vector-recall memory** |
| [`agentsea_bumblebee`](https://hexdocs.pm/agentsea_bumblebee) | [![Hex](https://img.shields.io/hexpm/v/agentsea_bumblebee.svg)](https://hex.pm/packages/agentsea_bumblebee) | in-process HF-model embedder **and Whisper STT** via Bumblebee + Nx (no API) |
| [`agentsea_ingest`](https://hexdocs.pm/agentsea_ingest) | [![Hex](https://img.shields.io/hexpm/v/agentsea_ingest.svg)](https://hex.pm/packages/agentsea_ingest) | Broadway pipeline: chunk → embed → store, with batching/backpressure |
| [`agentsea_evaluate`](https://hexdocs.pm/agentsea_evaluate) | [![Hex](https://img.shields.io/hexpm/v/agentsea_evaluate.svg)](https://hex.pm/packages/agentsea_evaluate) | concurrent metrics (exact-match, contains, LLM-as-judge) + aggregation |
| [`agentsea_guardrails`](https://hexdocs.pm/agentsea_guardrails) | [![Hex](https://img.shields.io/hexpm/v/agentsea_guardrails.svg)](https://hex.pm/packages/agentsea_guardrails) | input/output guardrail pipeline — max-length, blocklist, PII redaction, LLM moderation |
| [`agentsea_mcp`](https://hexdocs.pm/agentsea_mcp) | [![Hex](https://img.shields.io/hexpm/v/agentsea_mcp.svg)](https://hex.pm/packages/agentsea_mcp) | MCP client with **stdio** and **streamable-HTTP** transports; server tools adapted into agent `Tool.Spec`s |
| [`agentsea_surf`](https://hexdocs.pm/agentsea_surf) | [![Hex](https://img.shields.io/hexpm/v/agentsea_surf.svg)](https://hex.pm/packages/agentsea_surf) | Node/Playwright browser sidecar over a `Port`, exposed as agent tools |
| [`agentsea_voice`](https://hexdocs.pm/agentsea_voice) | [![Hex](https://img.shields.io/hexpm/v/agentsea_voice.svg)](https://hex.pm/packages/agentsea_voice) | `TTS`/`STT` behaviours + OpenAI (TTS+STT) and ElevenLabs (TTS) adapters over `Req` |

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

## Publishing

Each `apps/*` app publishes to Hex as its own package, and **all 14 are
live** (see the badges in the table above). See
[docs/PUBLISHING.md](docs/PUBLISHING.md) for the metadata, the umbrella
sibling-dependency mechanism (`HEX_PUBLISH=1`), the publish order, and the
commands.

## License

[Apache-2.0](LICENSE).
