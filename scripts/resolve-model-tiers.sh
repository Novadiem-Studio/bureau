#!/usr/bin/env bash
# Resolve per-role model tiers from model-policy.json + experiments + usage snapshot.
#
# Usage: ./scripts/resolve-model-tiers.sh [output-path]
# Default output: ~/.novadiem/resolved-model-tiers.json
#
# Env:
#   NOVADIEM_MODEL_EXPERIMENTS  comma-separated experiment ids (e.g. systemsmith-sonnet)
#   NOVADIEM_MODEL_POLICY       path to model-policy.json
#   NOVADIEM_USAGE_SNAPSHOT_PATH  usage snapshot for auto-activation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
POLICY_PATH="${NOVADIEM_MODEL_POLICY:-$FRAMEWORK_ROOT/config/model-policy.json}"
EXPERIMENTS_DIR="$FRAMEWORK_ROOT/config/experiments"
SNAPSHOT_PATH="${NOVADIEM_USAGE_SNAPSHOT_PATH:-$HOME/.novadiem/usage-snapshot.json}"
OUTPUT_PATH="${1:-$HOME/.novadiem/resolved-model-tiers.json}"
RESOLVED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if ! command -v jq >/dev/null 2>&1; then
  echo "resolve-model-tiers: jq required" >&2
  exit 1
fi

if [[ ! -f "$POLICY_PATH" ]]; then
  echo "resolve-model-tiers: policy not found: $POLICY_PATH" >&2
  exit 1
fi

usage_json='{}'
if [[ -f "$SNAPSHOT_PATH" ]]; then
  usage_json="$(jq -c '.claude // {}' "$SNAPSHOT_PATH")"
fi

manual_from_env="${NOVADIEM_MODEL_EXPERIMENTS:-}"
manual_from_policy="$(jq -r '.manual_experiments // [] | join(",")' "$POLICY_PATH")"
manual_ids="$(printf '%s,%s' "$manual_from_env" "$manual_from_policy" | tr ',' '\n' | sed '/^$/d' | jq -R . | jq -s .)"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/resolve-tiers.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

shopt -s nullglob
exp_files=("$EXPERIMENTS_DIR"/*.json)
if ((${#exp_files[@]})); then
  experiments_json="$(jq -s '.' "${exp_files[@]}")"
else
  experiments_json='[]'
fi

jq -n \
  --arg resolvedAt "$RESOLVED_AT" \
  --arg policyPath "$POLICY_PATH" \
  --arg snapshotPath "$SNAPSHOT_PATH" \
  --slurpfile policy "$POLICY_PATH" \
  --argjson usage "$usage_json" \
  --argjson manualIds "$manual_ids" \
  --argjson experiments "$experiments_json" \
  '
    def active_experiment($exp):
      ($exp.disabled // false) as $disabled
      | if $disabled then false
      else
        ($exp.activate_when // {}) as $when
        | if ($when.manual_only // false) then
            ($manualIds | index($exp.id)) != null
          else
            (if ($when | length) == 0 then false else true end)
            and (if ($when.sonnetBurnMode? // false) then ($usage.sonnetBurnMode == true) else true end)
            and (if ($when.weeklyUsedPercent_gte?) then
                  ($usage.weeklyUsedPercent != null and $usage.weeklyUsedPercent >= $when.weeklyUsedPercent_gte)
                else true end)
            and (if ($when.sessionUsedPercent_gte?) then
                  ($usage.sessionUsedPercent != null and $usage.sessionUsedPercent >= $when.sessionUsedPercent_gte)
                else true end)
          end
        end;

    ($policy[0].roles) as $roles
    | [ $experiments[] | select(active_experiment(.)) ] as $active
    | ($active | map(.overrides // {}) | add // {}) as $mergedOverrides
    | ($active | map(.conductor_notes // []) | add // []) as $notes
    | ($active | map(.id)) as $activeIds
    | {
        resolvedAt: $resolvedAt,
        policyPath: $policyPath,
        snapshotPath: $snapshotPath,
        usage: $usage,
        activeExperiments: $activeIds,
        conductorNotes: $notes,
        roles: (
          $roles
          | to_entries
          | map(
              .key as $role
              | .value as $cfg
              | ($mergedOverrides[$role] // null) as $expTier
              | ($cfg.lock // false) as $locked
              | (if $locked then $cfg.default_tier
                 elif $expTier != null then $expTier
                 else $cfg.default_tier
                 end) as $rawTier
              | ($cfg.allowed // null) as $allowed
              | (if $allowed != null and ($allowed | index($rawTier)) == null
                 then $cfg.default_tier else $rawTier end) as $tier
              | {
                  role: $role,
                  agent: $cfg.agent,
                  tier: $tier,
                  source: (
                    if $locked then "lock"
                    elif $expTier != null and $tier != $expTier then "rejected-override"
                    elif $expTier != null then ("experiment:" + ($activeIds | join(",")))
                    else "default"
                    end
                  ),
                  lock: $locked,
                  allowed: ($cfg.allowed // [])
                }
            )
          | INDEX(.role)
        )
      }
  ' >"$tmpdir/resolved.json"

mkdir -p "$(dirname "$OUTPUT_PATH")"
mv "$tmpdir/resolved.json" "$OUTPUT_PATH"
