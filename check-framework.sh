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

echo "== model tiers in feature workflow"
if ! grep -q 'premium' workflows/feature.md; then
  err "workflows/feature.md should reference premium tier for Architect/Challenger"
fi
if ! grep -q 'sonnet' workflows/feature.md; then
  err "workflows/feature.md should reference sonnet tier for Analyst/Cleric/Spellwright"
fi
if grep -qE 'deep-reasoning' workflows/feature.md; then
  err "workflows/feature.md uses stale deep-reasoning — use premium or sonnet (see orchestrator.md)"
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

if [[ "$errors" -gt 0 ]]; then
  echo "== $errors check(s) failed" >&2
  exit 1
fi
echo "== all checks passed"
exit 0
