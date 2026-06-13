#!/usr/bin/env bash
# check-framework.sh — lint agent-framework for mechanical consistency.
# Exit 0 = pass, 1 = failures printed to stderr.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
errors=0

err() { echo "ERROR: $*" >&2; errors=$((errors + 1)); }

echo "== workflow registry"
for wf in workflows/*.md; do
  base=$(basename "$wf" .md)
  [[ "$base" == "index" ]] && continue
  if ! grep -qE "\[${base}\]\(${base}\.md\)" workflows/index.md; then
    err "workflows/${base}.md not registered in workflows/index.md"
  fi
done

echo "== stale top-level output paths (agents/ + workflows/)"
# Forbidden: output/<artifact> — allowed: output/runs, output/README, legacy notes in orchestrator only
while IFS= read -r line; do
  err "stale path: $line"
done < <(rg -n 'output/(spec|plan|prompts|log|design|state)\.' agents workflows 2>/dev/null \
  | grep -v 'orchestrator.md' \
  | grep -v 'output/runs' \
  | grep -v 'output/README' \
  | grep -v 'RUN_DIR' \
  | grep -v 'run dir' \
  || true)

echo "== model routing policy"
[[ -f config/model-policy.json ]] || err "missing legacy config/model-policy.json"
[[ -f config/model-policy.v2.json ]] || err "missing config/model-policy.v2.json"
[[ -x scripts/resolve-model-routing.sh ]] || err "scripts/resolve-model-routing.sh missing or not executable"
if [[ -f config/model-policy.v2.json ]]; then
  if ! jq -e '.version == 2 and (.tiers | index("standard")) and (.tiers | index("strong")) and (.tiers | index("frontier"))' config/model-policy.v2.json >/dev/null; then
    err "config/model-policy.v2.json missing required v2 tiers"
  fi
  while IFS= read -r role; do
    err "config/model-policy.v2.json role has invalid default tier: $role"
  done < <(jq -r '
    .tiers as $tiers
    | .roles
    | to_entries[]
    | select(($tiers | index(.value.default_tier)) == null)
    | .key
  ' config/model-policy.v2.json 2>/dev/null || true)
fi
for adapter in config/runtimes/*.json; do
  [[ -e "$adapter" ]] || continue
  if ! jq -e '.runtime and .tiers.cheap and .tiers.standard and .tiers.strong and .tiers.frontier and .tiers.escalated' "$adapter" >/dev/null; then
    err "$adapter missing runtime or complete tier mapping"
  fi
done
for exp in config/model-experiments/*.json; do
  [[ -e "$exp" ]] || continue
  if ! jq -e '.id and (.overrides // {})' "$exp" >/dev/null; then
    err "$exp missing id or overrides"
  fi
done
if ! grep -q 'Architect.*strong' workflows/feature.md; then
  err "workflows/feature.md should reference strong tier for Architect"
fi
if ! grep -q 'Challenger.*strong' workflows/feature.md; then
  err "workflows/feature.md should reference strong tier for Challenger"
fi
if ! grep -q 'standard' workflows/feature.md; then
  err "workflows/feature.md should reference standard tier for utility roles"
fi
if grep -qE 'deep-reasoning' workflows/feature.md; then
  err "workflows/feature.md uses stale deep-reasoning — use provider-neutral tiers (see orchestrator.md)"
fi

echo "== agent handoff blocks"
for agent in agents/*.md; do
  base=$(basename "$agent")
  [[ "$base" == "orchestrator.md" ]] && continue
  if ! grep -qE 'Handoff|HANDOFF|VERDICT|FINDINGS|DESIGN:|COMPLETE|BUILT|RAN' "$agent"; then
    err "$agent missing expected handoff/verdict block marker"
  fi
  if ! grep -q 'RUN_DIR' "$agent"; then
    err "$agent missing RUN_DIR convention"
  fi
done

echo "== state template JSON"
if ! python3 -c "import json; json.load(open('templates/state.json'))"; then
  err "templates/state.json does not parse as JSON"
fi

echo "== check-drift.sh excludes .git"
if ! grep -qE '\.git' check-drift.sh; then
  err "check-drift.sh should exclude .git from diffs"
fi

echo "== git worktree docs and script"
[[ -f docs/git-worktree.md ]] || err "missing docs/git-worktree.md"
[[ -x scripts/run-worktree.sh ]] || err "scripts/run-worktree.sh missing or not executable"
if ! grep -q 'run-worktree' workflows/execute-plan.md; then
  err "workflows/execute-plan.md should reference run-worktree"
fi

if [[ "$errors" -gt 0 ]]; then
  echo "== $errors check(s) failed" >&2
  exit 1
fi
echo "== all checks passed"
exit 0
