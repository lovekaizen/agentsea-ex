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

for app in "${APPS[@]}"; do
  echo
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "==> [dry-run] building $app"
    ( cd "apps/$app" && mix hex.build )
    rm -f "apps/$app"/*.tar
  else
    echo "==> publishing $app"
    ( cd "apps/$app" && mix hex.publish $PUBLISH_FLAGS )
  fi
done

echo
if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry run OK — all ${#APPS[@]} packages build."
else
  echo "Published all ${#APPS[@]} packages."
fi
