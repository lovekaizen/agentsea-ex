# Publishing AgentSea to Hex

AgentSea is an umbrella, and **Hex publishes each `apps/*` app as its own
package** — there is no "umbrella package". This guide covers the metadata,
the umbrella-specific dependency wrinkle, the publish order, and the commands.

All 14 apps already carry the package metadata they need (`description`,
`licenses`, `maintainers`, `links`); see any `apps/*/mix.exs`.

> **Confirm before your first publish:** the license (`Apache-2.0`), the
> maintainer (`Michael Bello`), and the GitHub URL
> (`https://github.com/lovekaizen/agentsea-ex`) are set in every
> `apps/*/mix.exs` and in `hex_deps.exs`. Edit them if any are wrong.

## 1. Prerequisites

```bash
mix hex.user register   # or: mix hex.user auth   (existing account)
```

You must own (or be an owner of) each package name on Hex. The package name is
the app name, e.g. `agentsea_core`. If a name is taken you'll need to rename the
app or request ownership.

## 2. The umbrella dependency wrinkle

Hex packages can only depend on **published** packages, so a sibling dep written
as `{:agentsea_core, in_umbrella: true}` makes `mix hex.build` fail:

```
** (Mix) Stopping package build due to errors.
Dependencies excluded from the package (only Hex packages can be dependencies): agentsea_core
```

This repo solves it with `hex_deps.exs` (required at the top of each child
`mix.exs`). Sibling deps go through `AgentSea.HexDeps.sibling/1`, which returns:

- `{app, in_umbrella: true}` normally (local dev/test resolve from `apps/`), and
- `{app, "~> <version>"}` when **`HEX_PUBLISH=1`** is set (a real Hex version req).

So you never edit `mix.exs` to publish — you just set the env var:

```bash
HEX_PUBLISH=1 mix hex.build      # emits "agentsea_core ~> 0.1.0", builds the tarball
```

Keep `@version` in `hex_deps.exs` in sync with the apps' `version:` (all `0.1.0`).

## 3. Publish order

Publish in dependency order — a package can't be published until the packages it
requires already exist on Hex. The tiers (from the sibling graph):

1. **No siblings:** `agentsea_core`, `agentsea_voice`
2. **→ core:** `agentsea_crews`, `agentsea_embeddings`, `agentsea_evaluate`,
   `agentsea_gateway`, `agentsea_guardrails`, `agentsea_mcp`,
   `agentsea_providers`, `agentsea_structured`, `agentsea_surf`
3. **→ tier 2:** `agentsea_ingest` (→ embeddings),
   `agentsea_web` (→ core, gateway), `agentsea_bumblebee` (→ embeddings, voice)

## 4. Publish each app

From the app directory, with `HEX_PUBLISH=1`:

```bash
cd apps/agentsea_core
HEX_PUBLISH=1 mix hex.publish      # publishes the package AND its docs (see §5)
```

`mix hex.publish` shows the file list, deps, and metadata, then asks to confirm.
To publish just the package (no docs): `HEX_PUBLISH=1 mix hex.publish package`.

A convenience loop for the whole umbrella (review each prompt!):

```bash
for app in agentsea_core agentsea_voice \
           agentsea_crews agentsea_embeddings agentsea_evaluate agentsea_gateway \
           agentsea_guardrails agentsea_mcp agentsea_providers agentsea_structured agentsea_surf \
           agentsea_ingest agentsea_web agentsea_bumblebee; do
  (cd "apps/$app" && HEX_PUBLISH=1 mix hex.publish)
done
```

## 5. Docs on HexDocs

Every app already depends on `ex_doc` (`only: :dev`), so `mix hex.publish`
builds and ships per-package HexDocs automatically — nothing extra to do. To
(re)publish only docs for one app:

```bash
cd apps/<app> && HEX_PUBLISH=1 mix hex.publish docs
```

The umbrella root **also** builds one combined doc site across all 14 apps with
`mix docs` (→ `doc/`) — handy to host on GitHub Pages and link from each
package's `links`.

## 6. Releasing a new version

1. Bump `version:` in every `apps/*/mix.exs` and `@version` in `hex_deps.exs`
   (they move together).
2. Update `CHANGELOG`/README as needed.
3. Re-publish in the order above.

## Checklist

- [ ] `mix test` green; `mix format --check-formatted`; `mix credo`; `mix dialyzer`
- [ ] License / maintainer / GitHub URL confirmed in every `apps/*/mix.exs`
- [ ] `mix hex.user auth` done; you own each package name
- [ ] `HEX_PUBLISH=1 mix hex.build` succeeds in each app
- [ ] Published in dependency order (tier 1 → 2 → 3)
