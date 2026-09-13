#!/usr/bin/env bash
# run-series-resolve.sh — locate campaign + plan paths for The Envoy.
#
# Usage:
#   run-series-resolve.sh <path>
#
# <path> may be:
#   - a plan dir (contains INDEX.md), or
#   - a campaign dir (SUPERVISOR.md / HANDOFF.md here, INDEX.md here or in
#     build-plan/).
#
# Prints KEY=value lines. CHARTER, STATE, and HANDOFF are the literal MISSING
# when absent (Envoy seeds those from templates/run-series/). INDEX is always
# a real path on success.
#
# Exit:
#   0  INDEX found
#   1  argument / not a dir / no INDEX.md

PATH=/usr/bin:$PATH

usage() {
  echo "Usage: run-series-resolve.sh <path>" >&2
  exit 1
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
fi

if [ "$#" -ne 1 ]; then
  echo "run-series-resolve: expected one path" >&2
  usage
fi

RAW="$1"
if [ ! -d "$RAW" ]; then
  echo "run-series-resolve: not a directory: $RAW" >&2
  exit 1
fi

ABS="$(cd "$RAW" && pwd -P)" || {
  echo "run-series-resolve: cannot resolve: $RAW" >&2
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -f "$ABS/INDEX.md" ]; then
  PLAN_DIR="$ABS"
elif [ -f "$ABS/build-plan/INDEX.md" ]; then
  PLAN_DIR="$ABS/build-plan"
else
  echo "run-series-resolve: no INDEX.md in $ABS or $ABS/build-plan" >&2
  exit 1
fi

PLAN_PARENT="$(cd "$PLAN_DIR/.." && pwd -P)"

if [ -f "$ABS/SUPERVISOR.md" ]; then
  CAMPAIGN_DIR="$ABS"
elif [ -f "$PLAN_DIR/SUPERVISOR.md" ]; then
  CAMPAIGN_DIR="$PLAN_DIR"
elif [ -f "$PLAN_PARENT/SUPERVISOR.md" ] || [ -f "$PLAN_PARENT/HANDOFF.md" ]; then
  CAMPAIGN_DIR="$PLAN_PARENT"
else
  CAMPAIGN_DIR="$PLAN_DIR"
fi

resolve_optional() {
  name="$1"
  if [ -f "$CAMPAIGN_DIR/$name" ]; then
    printf '%s\n' "$CAMPAIGN_DIR/$name"
  elif [ -f "$PLAN_DIR/$name" ]; then
    printf '%s\n' "$PLAN_DIR/$name"
  else
    printf 'MISSING\n'
  fi
}

printf 'PLAN_DIR=%s\n' "$PLAN_DIR"
printf 'CAMPAIGN_DIR=%s\n' "$CAMPAIGN_DIR"
printf 'INDEX=%s\n' "$PLAN_DIR/INDEX.md"
printf 'CHARTER=%s\n' "$(resolve_optional SUPERVISOR.md)"
printf 'STATE=%s\n' "$(resolve_optional SUPERVISOR-STATE.md)"
printf 'HANDOFF=%s\n' "$(resolve_optional HANDOFF.md)"
printf 'TEMPLATES=%s\n' "$FRAMEWORK_ROOT/templates/run-series"
