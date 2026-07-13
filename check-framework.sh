#!/usr/bin/env bash
# check-framework.sh — lint agent-framework for mechanical consistency.
# Exit 0 = pass, 1 = failures printed to stderr.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
errors=0
warnings=0

err()  { echo "ERROR: $*" >&2; errors=$((errors + 1)); }
warn() { echo "WARN: $*";     warnings=$((warnings + 1)); }

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

echo "== run-dir documentation drift"
# Normal runs now write to RUN_DIR. Keep no-target fallback examples in the files
# that define startup/resume behavior, but flag older Archive/output phrasing elsewhere.
while IFS= read -r line; do
  err "stale RUN_DIR doc: $line"
done < <(rg -n 'output/runs/<task>/|agent-framework/output/runs|~/Code/novadiem/bureau/output/runs|In the machinery: `output/runs' . \
  -g '*.md' \
  -g '!output/runs/**' \
  -g '!ideas/**' \
  -g '!AGENTS.md' \
  -g '!CLAUDE.md' \
  -g '!README.md' \
  -g '!agents/orchestrator.md' \
  -g '!agents/witness.md' \
  -g '!docs/run-protocol.md' \
  2>/dev/null || true)

echo "== extracted-doc anchors"
grep -Fq '## Run directory, state management, and log format' agents/orchestrator.md \
  || err "agents/orchestrator.md missing run-protocol pointer heading"
grep -Fq '## Run accounting (close-out)' agents/orchestrator.md \
  || err "agents/orchestrator.md missing run-accounting pointer heading"
grep -Fq '## Startup read scope (token discipline)' agents/orchestrator.md \
  || err "agents/orchestrator.md missing startup read-scope heading"
always_core="$(awk '/\*\*Always-read core/{flag=1; next} /\*\*Load on demand/{flag=0} flag' agents/orchestrator.md)"
if printf '%s\n' "$always_core" | grep -Fq 'docs/run-accounting.md'; then
  err "agents/orchestrator.md startup core should not always-read run-accounting; load it at close-out"
fi
if printf '%s\n' "$always_core" | grep -Fq 'docs/model-routing-and-cast.md'; then
  err "agents/orchestrator.md startup core should not always-read model-routing-and-cast; load before first spawn"
fi
grep -Fq 'Workflow: <selected workflow id>' agents/orchestrator.md \
  || err "agents/orchestrator.md spawn template should pass selected workflow"
grep -Fq 'Role mode: <mode for this spawn' agents/orchestrator.md \
  || err "agents/orchestrator.md spawn template should pass role mode"
grep -Fq 'docs/model-routing-and-cast.md' agents/orchestrator.md \
  || err "agents/orchestrator.md missing model-routing module pointer"
grep -Fq 'agents/orchestrator.md` § Model routing, budget usage, and cast map' docs/model-routing-and-cast.md \
  || err "docs/model-routing-and-cast.md pointer-back should target the orchestrator summary heading"
grep -Fq 'docs/model-routing-and-cast.md` § Host policy - Claude Code (current)' README.md \
  || err "README.md should point Host policy readers at docs/model-routing-and-cast.md"
grep -Fq '| **The Delegate** | `agents/delegate.md` |' docs/model-routing-and-cast.md \
  || err "docs/model-routing-and-cast.md missing Delegate in cast map"
grep -Fq '| The Delegate | `agents/delegate.md` |' AGENTS.md \
  || err "AGENTS.md missing Delegate in agent table"
if grep -Fq 'Model tiers below' agents/orchestrator.md; then
  err "agents/orchestrator.md still points at removed Model tiers section"
fi
if grep -Fq 'agents/orchestrator.md` § Host policy' README.md; then
  err "README.md still points Host policy at agents/orchestrator.md"
fi
grep -Fq 'docs/existing-project-mode.md' agents/orchestrator.md \
  || err "agents/orchestrator.md missing existing-project module pointer"
grep -Fq 'docs/conductor-gates.md' agents/orchestrator.md \
  || err "agents/orchestrator.md missing conductor-gates module pointer"
if rg -n 'canonical source is `agents/orchestrator\.md`|canonical list there|defined in Review 1 above|inlined under Review 1|inline surface list above' agents/critic.md agents/critic >/dev/null 2>&1; then
  err "critic core/slices contain stale pre-split cross-reference or conductor-gates pointer"
fi
for slice in spec-plan prompts build-diff code-review; do
  [[ -f "agents/critic/${slice}.md" ]] \
    || err "missing agents/critic/${slice}.md"
  grep -Fq "agents/critic/${slice}.md" agents/critic.md \
    || err "agents/critic.md missing mode-slice pointer for ${slice}"
done
for slice in spec-plan prompts; do
  grep -Fq '**Email and SMS sends**' "agents/critic/${slice}.md" \
    || err "agents/critic/${slice}.md missing inlined external-action taxonomy"
  grep -Fq 'docs/external-action-boundary.md' "agents/critic/${slice}.md" \
    || err "agents/critic/${slice}.md missing external-action reciprocal sync note"
done
for slice in spec-plan prompts build-diff; do
  grep -Fq '`workflows/`' "agents/critic/${slice}.md" \
    || err "agents/critic/${slice}.md missing inlined canon/process surface list"
  grep -Fq 'docs/conductor-gates.md' "agents/critic/${slice}.md" \
    || err "agents/critic/${slice}.md missing conductor-gates reciprocal sync note"
done
grep -Fq 'agents/critic/spec-plan.md' docs/external-action-boundary.md \
  || err "docs/external-action-boundary.md reciprocal note should name critic spec-plan slice"
grep -Fq 'agents/critic/prompts.md' docs/external-action-boundary.md \
  || err "docs/external-action-boundary.md reciprocal note should name critic prompts slice"
grep -Fq 'agents/critic/build-diff.md' docs/conductor-gates.md \
  || err "docs/conductor-gates.md reciprocal note should name critic build-diff slice"
for module in agent-contracts workflow-authoring regression-fixtures canon-promotion failure-signatures; do
  [[ -f "docs/conventions/${module}.md" ]] \
    || err "missing docs/conventions/${module}.md"
  grep -Fq "docs/conventions/${module}.md" docs/conventions.md \
    || err "docs/conventions.md missing router pointer for ${module}"
done
if rg -n 'docs/conventions[.]md §' . -g '*.md' -g '*.sh' -g '!output/runs/**' -g '!check-framework.sh' >/dev/null 2>&1; then
  err "stale docs/conventions.md § section reference; point at docs/conventions/<module>.md"
fi
grep -Fq 'Reads (mode slice):' docs/conventions/agent-contracts.md \
  || err "docs/conventions/agent-contracts.md Challenger contract should include critic mode-slice input"
grep -Fq 'docs/conventions/' docs/conductor-gates.md \
  || err "docs/conductor-gates.md canon surface list should include docs/conventions/"
for slice in spec-plan prompts build-diff; do
  grep -Fq '`docs/conventions/`' "agents/critic/${slice}.md" \
    || err "agents/critic/${slice}.md canon/process surface list should include docs/conventions/"
done
grep -Fq 'cp "$ROOT/docs/conventions/"*.md' scripts/watcher.sh \
  || err "scripts/watcher.sh should stage docs/conventions modules with the conventions router"
[[ -f agents/modes/architect-execute-plan.md ]] \
  || err "missing agents/modes/architect-execute-plan.md"
[[ -f agents/modes/spellwright-execute-plan.md ]] \
  || err "missing agents/modes/spellwright-execute-plan.md"
grep -Fq 'agents/modes/architect-execute-plan.md' agents/architect.md \
  || err "agents/architect.md should point execute-plan chunking at its mode appendix"
grep -Fq 'agents/modes/spellwright-execute-plan.md' agents/prompt-engineer.md \
  || err "agents/prompt-engineer.md should point execute-plan prompt folders at its mode appendix"
[[ -f workflows/execute-plan/prompt-folder-format.md ]] \
  || err "missing workflows/execute-plan/prompt-folder-format.md"
[[ -f workflows/execute-plan/build-tail.md ]] \
  || err "missing workflows/execute-plan/build-tail.md"
grep -Fq 'workflows/execute-plan/prompt-folder-format.md' workflows/execute-plan.md \
  || err "workflows/execute-plan.md missing prompt-folder-format module pointer"
grep -Fq 'workflows/execute-plan/build-tail.md' workflows/execute-plan.md \
  || err "workflows/execute-plan.md missing build-tail module pointer"
grep -Fq 'workflows/execute-plan/prompt-folder-format.md' agents/modes/spellwright-execute-plan.md \
  || err "Spellwright execute-plan appendix should use prompt-folder-format module"
grep -Fq 'Production boundary — hard stop' workflows/execute-plan/build-tail.md \
  || err "execute-plan build-tail missing production boundary"
grep -Fq 'Close-out gates' workflows/execute-plan/build-tail.md \
  || err "execute-plan build-tail missing close-out gates"
grep -Fq 'run-worktree' workflows/execute-plan/build-tail.md \
  || err "execute-plan build-tail should reference run-worktree"
if rg -n 'workflows/execute-plan[.]md §|`execute-plan` § Prompt folder format|`execute-plan` § Production boundary|execute-plan[.]md` step [67]|execute-plan[.]md` carries in full' . -g '*.md' -g '*.sh' -g '!output/runs/**' -g '!output/archive/**' -g '!check-framework.sh' >/dev/null 2>&1; then
  err "stale execute-plan section reference; use execute-plan/prompt-folder-format.md or execute-plan/build-tail.md"
fi
if rg -n 'Prompt folder format' workflows/execute-plan.md >/dev/null 2>&1; then
  err "workflows/execute-plan.md should not inline Prompt folder format after split"
fi
grep -Fq '### Checkpoint type classification' docs/delegate-bridge.md \
  || err "docs/delegate-bridge.md missing checkpoint type classification anchor"
grep -Fq '## Section 5: Conductor checkpoint shim' docs/delegate-bridge.md \
  || err "docs/delegate-bridge.md missing Conductor checkpoint shim anchor"
[[ -f docs/delegate-bridge/v2-integrated.md ]] \
  || err "missing docs/delegate-bridge/v2-integrated.md"
[[ -f docs/delegate-bridge/watcher-v1.md ]] \
  || err "missing docs/delegate-bridge/watcher-v1.md"
grep -Fq 'docs/delegate-bridge/v2-integrated.md' docs/delegate-bridge.md \
  || err "docs/delegate-bridge.md missing v2 module pointer"
grep -Fq 'docs/delegate-bridge/watcher-v1.md' docs/delegate-bridge.md \
  || err "docs/delegate-bridge.md missing watcher module pointer"
grep -Fq 'CONDUCTOR-RETURN' docs/delegate-bridge/v2-integrated.md \
  || err "docs/delegate-bridge/v2-integrated.md missing CONDUCTOR-RETURN schema"
grep -Fq 'RECIPROCAL SYNC NOTE' docs/delegate-bridge/v2-integrated.md \
  || err "docs/delegate-bridge/v2-integrated.md missing schema reciprocal sync note"
grep -Fq '## Section 3: The load-bearing spawn invocation' docs/delegate-bridge/watcher-v1.md \
  || err "docs/delegate-bridge/watcher-v1.md missing watcher spawn section"
grep -Fq '## Section 4: Staging' docs/delegate-bridge/watcher-v1.md \
  || err "docs/delegate-bridge/watcher-v1.md missing watcher staging section"
grep -Fq 'docs/delegate-bridge.md § Checkpoint type classification' agents/orchestrator.md \
  || err "agents/orchestrator.md should link to docs/delegate-bridge.md § Checkpoint type classification"
if rg -n 'docs/delegate-bridge\.md § checkpoint types' . -g '*.md' -g '!output/runs/**' >/dev/null 2>&1; then
  err "stale delegate-bridge checkpoint-types anchor reference"
fi
if rg -n 'docs/delegate-bridge[.]md § v2|docs/delegate-bridge[.]md § Integrated topology|docs/delegate-bridge[.]md` v2|docs/delegate-bridge[.]md § [346789]' . -g '*.md' -g '*.sh' -g '!output/runs/**' -g '!check-framework.sh' >/dev/null 2>&1; then
  err "stale delegate-bridge implementation reference; use v2-integrated.md or watcher-v1.md"
fi
if grep -n 'Read `agents/orchestrator.md` in full\.' AGENTS.md CLAUDE.md >/dev/null 2>&1; then
  err "startup docs still say to read orchestrator in full; use startup read-scope policy"
fi

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

echo "== token-emit ownership coverage"
# Guard 1 (class-closure): every *-TOKEN-EVENT locked_append emit site must carry a
# governing `# OWNERSHIP-GATE:` marker naming the credential that proves the transcript
# it just read is really this run's. Two audit rounds each re-found the SAME class — a
# NEW emitter shipped un-gated (ownership-by-mention). This lint makes it impossible to
# add a token emitter without a conscious ownership decision: you must write a marker,
# and any emit in a file OUTSIDE the known set trips the "new emitter" check.
#
# The marker proves a CLAIM was made, not that it is TRUE (a lying marker would pass) —
# correctness of the three real gates is proved behaviorally by fixture 172. This lint's
# job is the demonstrated failure mode: forgetting. See spec .bureau/runs/20260711-class-closure.
#
# Emit-site detector: a NON-COMMENT line calling `locked_append` whose appended string is
# a token event — matched by a literal `TOKEN-EVENT` (E2/E3/E4) OR the `EVENT_PREFIX`
# variable (E1 conductor-stop.sh, whose prefix is `$EVENT_PREFIX` = CONDUCTOR/DELEGATE-
# TOKEN-EVENT). Leading-`#` comment lines are stripped first so a prose mention of
# `locked_append` (append-reviewer-tokens.sh:10) is never counted.
OWNERSHIP_EMITTERS=(scripts/conductor-stop.sh scripts/subagent-stop.sh scripts/append-reviewer-tokens.sh)

# Count emit sites and markers per known emitter; require markers >= emits (count-parity).
# Coarse on purpose (no fragile line-window): its guarantee is "you cannot add a 4th emit
# to these scripts without adding a marker," which count-parity delivers.
for emitter in "${OWNERSHIP_EMITTERS[@]}"; do
  if [[ ! -f "$emitter" ]]; then
    err "token-emit ownership: known emitter $emitter is missing — update OWNERSHIP_EMITTERS in check-framework.sh"
    continue
  fi
  # Emit sites: non-comment locked_append lines referencing a token event.
  emit_count=$(grep -vE '^[[:space:]]*#' "$emitter" \
    | grep -E 'locked_append' \
    | grep -cE 'TOKEN-EVENT|EVENT_PREFIX' || true)
  emit_count=${emit_count:-0}
  # Markers: `# OWNERSHIP-GATE:` with a NON-EMPTY body after the colon (a bare marker
  # naming no credential does not satisfy — the author must name what gates the emit).
  marker_count=$(grep -cE '^[[:space:]]*# *OWNERSHIP-GATE:[[:space:]]*[^[:space:]]' "$emitter" || true)
  marker_count=${marker_count:-0}
  if [[ "$marker_count" -lt "$emit_count" ]]; then
    err "token-emit ownership: $emitter has $emit_count *-TOKEN-EVENT emit site(s) but only $marker_count '# OWNERSHIP-GATE:' marker(s) with a non-empty body — every emit branch must name the credential that gates it"
  fi
done

# New-file escape hatch: any *-TOKEN-EVENT emit in a scripts/*.sh OUTSIDE the known set
# is a brand-new emitter the count-parity check above cannot see. Flag it so a future
# emitter anywhere trips the lint until it is registered above and marked.
for f in scripts/*.sh; do
  [[ -e "$f" ]] || continue
  known=0
  for emitter in "${OWNERSHIP_EMITTERS[@]}"; do
    [[ "$f" == "$emitter" ]] && known=1 && break
  done
  [[ "$known" -eq 1 ]] && continue
  if grep -vE '^[[:space:]]*#' "$f" | grep -E 'locked_append' | grep -qE 'TOKEN-EVENT|EVENT_PREFIX'; then
    err "new token emitter $f not in the ownership-coverage known set — add it to OWNERSHIP_EMITTERS in check-framework.sh and place an '# OWNERSHIP-GATE:' marker on its emit branch"
  fi
done

echo "== unguarded jq on STATE_JSON (F4 structural guard, OQ-3)"
# The F4 abort was a single unguarded jq on $STATE_JSON at STATEMENT scope
# (account-run.sh:589, `memory_type=$(jq -r … "$STATE_JSON")` with no 2>/dev/null): a
# corrupt/non-object state.json made that jq exit non-zero, which under `set -euo
# pipefail` aborted the whole script BEFORE any accounting.json was written. Fixture
# 177 is the behavioral standing guard; this is the STRUCTURAL one, so a future edit
# that reintroduces an unguarded top-level jq read of state.json trips CI instead of
# silently reopening F4.
#
# The rule (mirrors the real safe/unsafe split in account-run.sh): a jq read of
# "$STATE_JSON" / state.json that begins at COLUMN 0 (statement scope, not lexically
# nested inside an already-validated `if`/`case` block) MUST either carry `2>/dev/null`
# OR be the `jq -e 'type=="object"'` validate-once itself. Every legitimately-safe
# read in account-run.sh is EITHER indented (nested inside a block whose condition
# already type-gated the object) OR is the validator OR already has `2>/dev/null`; the
# F4 bug was the one column-0, unguarded, non-validator read. Scoped to the accounting
# scripts that read the run's state.json under set -e.
for scr in scripts/account-run.sh scripts/account-tokens.sh; do
  [[ -f "$scr" ]] || continue
  # Column-0 lines (no leading whitespace) that call jq AND read STATE_JSON/state.json.
  while IFS= read -r badline; do
    # exempt: the validate-once guard itself, and any line already carrying 2>/dev/null.
    printf '%s' "$badline" | grep -qE "type *== *\"object\"" && continue
    printf '%s' "$badline" | grep -qE '2>/dev/null|2> */dev/null' && continue
    err "unguarded jq on state.json at statement scope in $scr — reintroduces F4 (a corrupt state.json aborts the script under set -e before accounting.json is written). Add 2>/dev/null (and a fallback), or gate it behind a validated-object precondition: ${badline}"
  done < <(grep -nE '^jq .*(\$STATE_JSON|state\.json)|^[a-zA-Z_][a-zA-Z0-9_]*=\$\(jq .*(\$STATE_JSON|state\.json)' "$scr" || true)
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
if ! grep -q 'run-worktree' workflows/execute-plan/build-tail.md; then
  err "workflows/execute-plan/build-tail.md should reference run-worktree"
fi

echo "== orchestrator.md regrowth guard"
# agents/orchestrator.md is the Conductor's core context, loaded (in part) on
# every run's startup. Idea #19 (the Conductor context diet, shipped 2026-07-09)
# trimmed it hard: it was 465 lines right after that refactor. It keeps regrowing
# — 889 lines as of 2026-07-09 — which works directly against the context diet.
# ORCHESTRATOR_MD_BUDGET is a documented soft ceiling: a WARNING (advisory), never
# an `err` — a hard fail on line count is too brittle for prose that legitimately
# grows a little. 925 = 889 baseline + ~36 lines (~4%) of headroom, so it does not
# fire today but trips on further growth, forcing a conscious "trim or raise the
# budget" decision instead of silent creep. When #19's rationale says the file
# should shrink, LOWER this number rather than let it drift up.
ORCHESTRATOR_MD_BUDGET=925
orch_lines=$(wc -l < agents/orchestrator.md | tr -d '[:space:]')
if [[ "$orch_lines" -gt "$ORCHESTRATOR_MD_BUDGET" ]]; then
  warn "agents/orchestrator.md is ${orch_lines} lines, over the ${ORCHESTRATOR_MD_BUDGET}-line budget — it is the Conductor's startup context and this works against idea #19 (the Conductor context diet). Trim it back or, if the growth is justified, raise ORCHESTRATOR_MD_BUDGET in check-framework.sh with a note why."
fi

echo "== name lint"
# Advisory warnings only. Does NOT touch `errors` or the exit code.
# A warning means a file name looks vague. The right response is to rename the
# file or add its basename (without extension) to NAME_ALLOWLIST below — never
# weaken a pattern, never treat a warning as a build failure (EC 7).

# Reserved-generic words (FR 4a).
RESERVED_GENERIC=(util helper run test common misc shared tools lib core temp tmp new old fix patch)

# Allowlist: basenames (without extension) that are explicitly exempt from FR 4.
# Pre-populated from the current tree (AC 5). Add to this list to silence a false positive.
NAME_ALLOWLIST=(
  account-run await-verdict delegate-launcher install-usage-poller ledger-append
  notify-escalation poll-usage-snapshot preflight promote-fixtures resolve-model-routing
  resolve-model-tiers run-worktree summary-gen sync-chatgpt-export verdict-write watcher
  check-drift check-framework
  bug-fix code-review copy-review docs-reconcile execute-plan feature message-framing
  operational-build studio-briefing
  index README CLAUDE MEMORY LORE
)

# Helper: returns 0 (true) if $1 is in NAME_ALLOWLIST or is a meta-file basename.
is_allowlisted() {
  local stem="$1"
  local item
  for item in "${NAME_ALLOWLIST[@]}"; do
    [[ "$stem" == "$item" ]] && return 0
  done
  return 1
}

# Collect in-scope files: scripts/*.sh, root *.sh, workflows/*.md (minus index.md),
# runbooks/*.md (only if runbooks/ exists). Pruning output/, .git/, node_modules/
# is belt-and-suspenders: the globs below don't reach them, but an explicit prune
# prevents a future scope-widening from pulling them in (EC 4, EC 6).
LINT_FILES=()
for f in scripts/*.sh; do [[ -e "$f" ]] && LINT_FILES+=("$f"); done
for f in ./*.sh;        do [[ -e "$f" ]] && LINT_FILES+=("$f"); done
for f in workflows/*.md; do
  [[ -e "$f" ]] || continue
  [[ "$(basename "$f" .md)" == "index" ]] && continue
  LINT_FILES+=("$f")
done
if [[ -d runbooks ]]; then
  for f in runbooks/*.md; do [[ -e "$f" ]] && LINT_FILES+=("$f"); done
fi

# Near-duplicate detection (FR 4d): collect stems per directory before the main loop.
# Algorithm (bash 3.2 compatible — no associative arrays):
#   1. Collect all stems (basename without extension) for files in a given directory.
#   2. For each stem that ends in a single digit: strip that trailing digit to get
#      a candidate stem.
#   3. If the candidate stem exists in the same directory's stem list: it is a
#      near-duplicate pair. Warn once for the file whose stem ends in the digit.
# DIGIT-ONLY: single-trailing-alpha-char stripping is EXCLUDED — it fires on
# legitimate singular/plural pairs (log/logs, tier/tiers) and is not a reliable smell.
# Must NOT fire on resolve-model-routing vs resolve-model-tiers (multi-char difference).
# MUST fire on run2.sh when run.sh exists; on feature2.md when feature.md exists.

# Build per-directory stem lists from LINT_FILES.
NEAR_DUP_WARNS=()  # paths that triggered a near-dup warning (to suppress re-warn in main loop)

_dirs=()
for f in "${LINT_FILES[@]}"; do
  d="$(dirname "$f")"
  local_found=0
  for existing in "${_dirs[@]:-}"; do
    [[ "$existing" == "$d" ]] && local_found=1 && break
  done
  [[ "$local_found" -eq 0 ]] && _dirs+=("$d")
done

for dir in "${_dirs[@]}"; do
  # Collect stems in this directory from LINT_FILES.
  dir_stems=()
  for f in "${LINT_FILES[@]}"; do
    [[ "$(dirname "$f")" == "$dir" ]] || continue
    fname="$(basename "$f")"
    stem="${fname%.*}"
    dir_stems+=("$stem")
  done
  # For each stem ending in a single digit, check if the stem-minus-digit exists.
  for stem in "${dir_stems[@]}"; do
    last_char="${stem: -1}"
    case "$last_char" in
      [0-9])
        candidate="${stem%?}"
        [[ -z "$candidate" ]] && continue  # stem is pure digit — caught by FR 4b
        for other in "${dir_stems[@]}"; do
          if [[ "$other" == "$candidate" ]]; then
            # Find the file path for this stem so we can warn with a path.
            for f in "${LINT_FILES[@]}"; do
              [[ "$(dirname "$f")" == "$dir" ]] || continue
              fname2="$(basename "$f")"
              fstem="${fname2%.*}"
              if [[ "$fstem" == "$stem" ]]; then
                NEAR_DUP_WARNS+=("$f:near-duplicate of ${dir}/${candidate}.* (trailing digit suffix)")
              fi
            done
            break
          fi
        done
        ;;
    esac
  done
done

# Main lint loop: one WARN per file, collecting all reasons before emitting (C2).
for f in "${LINT_FILES[@]:-}"; do
  # Skip output/, .git/, node_modules/ (belt-and-suspenders, EC 4).
  case "$f" in
    ./output/*|output/*|./.git/*|.git/*|./node_modules/*|node_modules/*) continue ;;
  esac

  fname="$(basename "$f")"
  stem="${fname%.*}"

  # Skip allowlisted names and meta-files (FR 5, EC 5).
  is_allowlisted "$stem" && continue

  reasons=()

  # FR 4a: exact match against reserved-generic list.
  for word in "${RESERVED_GENERIC[@]}"; do
    if [[ "$stem" == "$word" ]]; then
      reasons+=("reserved generic name '$stem'")
      break
    fi
  done

  # FR 4b: all-digit stem, or single-word stem shorter than 4 chars (no - or _).
  if [[ "$stem" =~ ^[0-9]+$ ]]; then
    reasons+=("basename is all digits")
  elif [[ ! "$stem" =~ [-_] ]] && [[ "${#stem}" -lt 4 ]]; then
    reasons+=("single-word stem shorter than 4 chars ('$stem')")
  fi

  # FR 4c: temp-looking name patterns.
  case "$stem" in
    tmp-*|temp-*|bak-*)
      reasons+=("temp-looking prefix in name")
      ;;
  esac
  case "$stem" in
    *-bak|*-tmp|*-old)
      reasons+=("temp-looking suffix in name")
      ;;
  esac

  # FR 4d: near-duplicate (collected above — check if this file was flagged).
  for entry in "${NEAR_DUP_WARNS[@]:-}"; do
    flagged_path="${entry%%:*}"
    flagged_reason="${entry#*:}"
    if [[ "$flagged_path" == "$f" ]]; then
      reasons+=("$flagged_reason")
      break
    fi
  done

  # Emit ONE warn() per file even if multiple reasons fired (C2 — one WARN per file).
  if [[ "${#reasons[@]}" -gt 0 ]]; then
    reason_str="${reasons[0]}"
    i=1
    while [[ "$i" -lt "${#reasons[@]}" ]]; do
      reason_str="${reason_str}; ${reasons[$i]}"
      i=$((i + 1))
    done
    warn "$f: $reason_str"
  fi
done

echo "== name lint: ${warnings} warnings"

# StatusLine setup health (budget-feed health). The usage snapshot is now written by
# scripts/statusline-usage.sh, wired as the Claude Code statusLine in ~/.claude/settings.json.
# The retired launchd poller (com.novadiem.usage-snapshot) is gone. Warn if the statusLine
# wiring is missing or the script is absent/non-executable — never fail, it is an environment
# concern, not a repo defect.
STATUSLINE_SCRIPT="$ROOT/scripts/statusline-usage.sh"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if [[ ! -f "$STATUSLINE_SCRIPT" ]]; then
  warn "scripts/statusline-usage.sh is missing — budget snapshot will not update"
elif [[ ! -x "$STATUSLINE_SCRIPT" ]]; then
  warn "scripts/statusline-usage.sh is not executable — budget snapshot will not update; run: chmod +x $STATUSLINE_SCRIPT"
elif [[ -f "$CLAUDE_SETTINGS" ]]; then
  if ! grep -q "statusline-usage.sh" "$CLAUDE_SETTINGS" 2>/dev/null; then
    warn "~/.claude/settings.json has no statusLine pointing at statusline-usage.sh — budget snapshot will not update after API responses"
  fi
else
  warn "~/.claude/settings.json not found — statusLine wiring cannot be verified; budget snapshot may not update"
fi

# Hook-wiring gate (FR 11, AC-17). Hard-fails when SubagentStop/Stop hooks are missing
# or their target scripts are absent/non-executable. Uses jq for all settings.json
# parsing (ugrep-immune — EC 10). The statusLine block above uses bare grep only for an
# advisory warn; this gate hard-fails so it must NOT use bare grep.
if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
  err "~/.claude/settings.json not found — SubagentStop and Stop hook wiring cannot be verified; token capture will not fire"
else
  # Read SubagentStop hook commands using jq (ugrep-immune):
  subagent_cmd=$(jq -r '[.hooks.SubagentStop[]?.hooks[]?.command] | join("\n")' "$CLAUDE_SETTINGS" 2>/dev/null || echo "")
  stop_cmd=$(jq -r '[.hooks.Stop[]?.hooks[]?.command] | join("\n")' "$CLAUDE_SETTINGS" 2>/dev/null || echo "")

  # Suffix check using jq endswith (NOT grep) (AC-17 compliance):
  subagent_ok=$(printf '%s' "$subagent_cmd" | jq -Rrs 'split("\n") | any(endswith("scripts/subagent-stop.sh"))')
  stop_ok=$(printf '%s' "$stop_cmd" | jq -Rrs 'split("\n") | any(endswith("scripts/conductor-stop.sh"))')

  if [[ "$subagent_ok" != "true" ]]; then
    err "SubagentStop hook missing or scripts/subagent-stop.sh not wired — token capture will not fire"
  elif [[ ! -f "$ROOT/scripts/subagent-stop.sh" ]] || [[ ! -x "$ROOT/scripts/subagent-stop.sh" ]]; then
    err "SubagentStop hook wired but $ROOT/scripts/subagent-stop.sh does not exist or is not executable — token capture will not fire"
  fi

  if [[ "$stop_ok" != "true" ]]; then
    err "Stop hook missing or scripts/conductor-stop.sh not wired — conductor token capture will not fire"
  elif [[ ! -f "$ROOT/scripts/conductor-stop.sh" ]] || [[ ! -x "$ROOT/scripts/conductor-stop.sh" ]]; then
    err "Stop hook wired but $ROOT/scripts/conductor-stop.sh does not exist or is not executable — conductor token capture will not fire"
  fi
fi

if [[ "$errors" -gt 0 ]]; then
  echo "== $errors check(s) failed" >&2
  exit 1
fi
echo "== all checks passed"
exit 0
