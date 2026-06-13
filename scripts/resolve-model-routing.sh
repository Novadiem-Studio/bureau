#!/usr/bin/env bash
# Resolve provider-neutral per-role model routing from model-policy.v2.json + runtime adapter.
#
# Usage: ./scripts/resolve-model-routing.sh [output-path]
# Default output: ~/.novadiem/resolved-model-routing.json
#
# Env:
#   NOVADIEM_MODEL_RUNTIME       runtime name (openai, claude, openrouter, hermes)
#   NOVADIEM_MODEL_POLICY_V2     path to provider-neutral policy
#   NOVADIEM_MODEL_RUNTIME_PATH  path to runtime adapter JSON
#   NOVADIEM_MODEL_EXPERIMENTS   comma-separated provider-neutral experiment ids
#   NOVADIEM_MODEL_EXPERIMENTS_DIR  provider-neutral experiments dir
#   NOVADIEM_USAGE_SNAPSHOT_PATH usage snapshot for budget context

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
POLICY_PATH="${NOVADIEM_MODEL_POLICY_V2:-$FRAMEWORK_ROOT/config/model-policy.v2.json}"
EXPERIMENTS_DIR="${NOVADIEM_MODEL_EXPERIMENTS_DIR:-$FRAMEWORK_ROOT/config/model-experiments}"
SNAPSHOT_PATH="${NOVADIEM_USAGE_SNAPSHOT_PATH:-$HOME/.novadiem/usage-snapshot.json}"
OUTPUT_PATH="${1:-$HOME/.novadiem/resolved-model-routing.json}"
RESOLVED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if ! command -v jq >/dev/null 2>&1; then
  echo "resolve-model-routing: jq required" >&2
  exit 1
fi

if [[ ! -f "$POLICY_PATH" ]]; then
  echo "resolve-model-routing: policy not found: $POLICY_PATH" >&2
  exit 1
fi

runtime_name="${NOVADIEM_MODEL_RUNTIME:-$(jq -r '.default_runtime // "openai"' "$POLICY_PATH")}"
RUNTIME_PATH="${NOVADIEM_MODEL_RUNTIME_PATH:-$FRAMEWORK_ROOT/config/runtimes/${runtime_name}.json}"

if [[ ! -f "$RUNTIME_PATH" ]]; then
  echo "resolve-model-routing: runtime adapter not found: $RUNTIME_PATH" >&2
  exit 1
fi

usage_json='{}'
if [[ -f "$SNAPSHOT_PATH" ]]; then
  usage_json="$(jq -c '.' "$SNAPSHOT_PATH")"
fi

manual_from_env="${NOVADIEM_MODEL_EXPERIMENTS:-}"
manual_from_policy="$(jq -r '.manual_experiments // [] | join(",")' "$POLICY_PATH")"
manual_ids="$(printf '%s,%s' "$manual_from_env" "$manual_from_policy" | tr ',' '\n' | sed '/^$/d' | jq -R . | jq -s .)"

shopt -s nullglob
exp_files=("$EXPERIMENTS_DIR"/*.json)
if ((${#exp_files[@]})); then
  experiments_json="$(jq -s '.' "${exp_files[@]}")"
else
  experiments_json='[]'
fi

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/resolve-routing.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

jq -n \
  --arg resolvedAt "$RESOLVED_AT" \
  --arg policyPath "$POLICY_PATH" \
  --arg runtimePath "$RUNTIME_PATH" \
  --arg experimentsDir "$EXPERIMENTS_DIR" \
  --arg snapshotPath "$SNAPSHOT_PATH" \
  --arg runtimeName "$runtime_name" \
  --slurpfile policy "$POLICY_PATH" \
  --slurpfile runtime "$RUNTIME_PATH" \
  --argjson usage "$usage_json" \
  --argjson manualIds "$manual_ids" \
  --argjson experiments "$experiments_json" \
  '
    def as_bool:
      if type == "boolean" then .
      elif type == "string" then false
      else false
      end;

    def active_experiment($exp):
      ($exp.activate_when // {}) as $when
      | if ($when.manual_only // false) then
          ($manualIds | index($exp.id)) != null
        else
          (if ($when | length) == 0 then false else true end)
          and (if ($when.runtime?) then $when.runtime == $runtimeName else true end)
          and (if ($when.manual_id?) then (($manualIds | index($when.manual_id)) != null) else true end)
        end;

    def capability_warning($runtimeCaps; $roleCfg):
      if (($roleCfg.fresh_context_required // false) == true)
         and (($runtimeCaps.supports_fresh_context_subagents | as_bool) != true)
      then ["fresh_context_required_but_unconfirmed"]
      else []
      end;

    ($policy[0]) as $policyDoc
    | ($runtime[0]) as $runtimeDoc
    | ($policyDoc.tiers // []) as $knownTiers
    | ($runtimeDoc.tiers // {}) as $runtimeTiers
    | ($runtimeDoc.capabilities // {}) as $runtimeCaps
    | [ $experiments[] | select(active_experiment(.)) ] as $active
    | ($active | map(.overrides // {}) | add // {}) as $mergedOverrides
    | ($active | map(.conductor_notes // []) | add // []) as $notes
    | ($active | map(.id)) as $activeIds
    | ($policyDoc.roles) as $roles
    | {
        resolvedAt: $resolvedAt,
        policyPath: $policyPath,
        runtimePath: $runtimePath,
        experimentsDir: $experimentsDir,
        snapshotPath: $snapshotPath,
        runtime: $runtimeDoc.runtime,
        runtimeDescription: ($runtimeDoc.description // null),
        usage: $usage,
        activeExperiments: $activeIds,
        conductorNotes: $notes,
        capabilityWarnings: [],
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
              | ($cfg.allowed // []) as $allowed
              | (if ($knownTiers | index($rawTier)) == null then $cfg.default_tier
                 elif ($allowed | index($rawTier)) == null then $cfg.default_tier
                 else $rawTier
                 end) as $tier
              | ($runtimeTiers[$tier] // {}) as $runtimeTier
              | {
                  role: $role,
                  agent: $cfg.agent,
                  tier: $tier,
                  model: ($runtimeTier.model // null),
                  reasoningEffort: ($runtimeTier.reasoning_effort // null),
                  serviceTier: ($runtimeTier.service_tier // null),
                  runtimeNotes: ($runtimeTier.notes // null),
                  source: (
                    if $locked then "lock"
                    elif $expTier != null and $tier != $expTier then "rejected-override"
                    elif $expTier != null then ("experiment:" + ($activeIds | join(",")))
                    else "default"
                    end
                  ),
                  freshContextRequired: ($cfg.fresh_context_required // false),
                  capabilityWarnings: capability_warning($runtimeCaps; $cfg),
                  allowed: $allowed,
                  escalateWhen: ($cfg.escalate_when // []),
                  deescalateWhen: ($cfg.deescalate_when // [])
                }
            )
          | INDEX(.role)
        )
      }
    | .capabilityWarnings = (
        [.roles[] | .capabilityWarnings[]?] | unique
      )
  ' >"$tmpdir/resolved.json"

mkdir -p "$(dirname "$OUTPUT_PATH")"
mv "$tmpdir/resolved.json" "$OUTPUT_PATH"
echo "resolved model routing -> $OUTPUT_PATH"
