#!/usr/bin/env bash
#
# Publish every AgentSea app to Hex, in dependency order.
#
# Usage:
#   scripts/publish.sh            # publish all (prompts to confirm each)
#   scripts/publish.sh --dry-run  # build each package, don't publish (verify)
#   scripts/publish.sh --yes      # publish all without per-app confirmation
#   scripts/publish.sh --replace  # overwrite an already-published version
#                                 # (allowed only within ~1h of first publish;
#                                 #  otherwise bump the version). Harmless for
#                                 #  not-yet-published apps.
#
# Sets HEX_PUBLISH=1 so sibling umbrella deps resolve as Hex version
# requirements (see hex_deps.exs and docs/PUBLISHING.md). Run `mix hex.user auth`
# first. Stops on the first failure.

set -eo pipefail

cd "$(dirname "$0")/.."

DRY_RUN=0
PUBLISH_FLAGS=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --yes) PUBLISH_FLAGS="$PUBLISH_FLAGS --yes" ;;
    --replace) PUBLISH_FLAGS="$PUBLISH_FLAGS --replace" ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

# Dependency order: a package can only be published after its siblings exist.
APPS=(
  agentsea_core agentsea_voice
  agentsea_crews agentsea_embeddings agentsea_evaluate agentsea_gateway
  agentsea_guardrails agentsea_mcp agentsea_providers agentsea_structured agentsea_surf
  agentsea_ingest agentsea_web agentsea_bumblebee
)

export HEX_PUBLISH=1

# Publishing compiles each app with HEX_PUBLISH=1, where sibling deps are Hex
# version requirements — so each app's already-published siblings must be
# fetched from Hex first (`mix deps.get`). That touches the shared mix.lock and
# pulls agentsea_* into deps/; restore the umbrella's local state on exit.
if [ "$DRY_RUN" -eq 0 ]; then
  LOCK_BACKUP="$(mktemp)"
  cp mix.lock "$LOCK_BACKUP"
  cleanup() {
    cp "$LOCK_BACKUP" mix.lock 2>/dev/null || true
    rm -f "$LOCK_BACKUP"
    rm -rf deps/agentsea_* 2>/dev/null || true
    echo "Restored mix.lock; run \`mix deps.get\` to refetch umbrella deps locally."
  }
  trap cleanup EXIT
fi

for app in "${APPS[@]}"; do
  echo
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "==> [dry-run] building $app"
    ( cd "apps/$app" && mix hex.build )
    rm -f "apps/$app"/*.tar
  else
    echo "==> publishing $app"
    # deps.get fetches the published siblings so the app compiles for publish.
    ( cd "apps/$app" && mix deps.get && mix hex.publish $PUBLISH_FLAGS )
  fi
done

echo
if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry run OK — all ${#APPS[@]} packages build."
else
  echo "Published all ${#APPS[@]} packages."
fi
