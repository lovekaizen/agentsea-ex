# Publishing AgentSea to Hex

AgentSea is an umbrella, and **Hex publishes each `apps/*` app as its own
package** — there is no "umbrella package". This guide covers the metadata,
the umbrella-specific dependency wrinkle, the publish order, and the commands.

All 14 apps already carry the package metadata they need: `description`,
`licenses: ["Apache-2.0"]`, `maintainers: ["lovekaizen"]`, `links` (GitHub), and
a `CHANGELOG.md` (Hex bundles it automatically and shows it on the package page).
See any `apps/*/mix.exs`.

> **One thing to confirm before your first publish:** the GitHub URL
> (`https://github.com/lovekaizen/agentsea-ex`) in every `apps/*/mix.exs`. The
> license (Apache-2.0) and maintainer (lovekaizen) are set.

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

## 4. Publish

The repo ships a one-shot script that publishes all apps in the right order,
setting `HEX_PUBLISH=1` for you:

```bash
scripts/publish.sh --dry-run   # build every package without publishing (verify)
scripts/publish.sh             # publish all, prompting to confirm each
scripts/publish.sh --yes       # publish all, no per-app prompt
scripts/publish.sh --replace   # overwrite an already-published version
```

It stops on the first failure. If a run got partway (some apps already
published), re-run with `--replace`: Hex requires `--replace` to overwrite an
existing release — it's allowed only within ~1 hour of the original publish,
after which you must bump the version. `--replace` is harmless for apps that
aren't published yet, so `scripts/publish.sh --replace --yes` cleanly finishes a
partial run (re-pushing the ones already up and publishing the rest).

To do a single app by hand instead:

```bash
cd apps/agentsea_core
HEX_PUBLISH=1 mix hex.publish            # package + docs
HEX_PUBLISH=1 mix hex.publish package    # package only (no docs)
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
- [ ] GitHub URL confirmed in every `apps/*/mix.exs` (license + maintainer are set)
- [ ] `CHANGELOG.md` updated (date the `0.1.0` entry on release)
- [ ] `mix hex.user auth` done; you own each package name
- [ ] `scripts/publish.sh --dry-run` passes
- [ ] `scripts/publish.sh` (publishes in dependency order)
