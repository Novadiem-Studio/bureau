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

# Usage-poller install drift (budget-feed health). The poller is an optional launchd agent
# installed OUTSIDE the repo; if its plist points at a script path that no longer resolves
# (e.g. after the framework was relocated), the budget snapshot silently freezes. This bit us
# 2026-06-22: the plist still pointed at a retired AI_skills/ path, so the feed was dead ~19h
# undetected and a run reported a stale budget as live. Warn, never fail — it is an
# environment/install concern, not a repo defect.
POLLER_PLIST="$HOME/Library/LaunchAgents/com.novadiem.usage-snapshot.plist"
if [[ -f "$POLLER_PLIST" ]]; then
  poller_script="$(grep -m1 -o '<string>[^<]*poll-usage-snapshot\.sh</string>' "$POLLER_PLIST" 2>/dev/null | sed -E 's#</?string>##g')" || poller_script=""
  if [[ -z "$poller_script" ]]; then
    warn "usage-poller plist present but lists no poll-usage-snapshot.sh path: $POLLER_PLIST"
  elif [[ ! -f "$poller_script" ]]; then
    warn "usage-poller plist points at a missing script ($poller_script) — budget snapshot is frozen; re-run scripts/install-usage-poller.sh"
  elif [[ "$poller_script" != "$ROOT/scripts/poll-usage-snapshot.sh" ]]; then
    warn "usage-poller plist points at $poller_script, not this install ($ROOT/scripts/poll-usage-snapshot.sh) — likely a relocated framework; re-run scripts/install-usage-poller.sh"
  fi
fi

if [[ "$errors" -gt 0 ]]; then
  echo "== $errors check(s) failed" >&2
  exit 1
fi
echo "== all checks passed"
exit 0
