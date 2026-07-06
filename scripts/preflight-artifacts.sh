#!/usr/bin/env bash
# scripts/preflight-artifacts.sh
# Read-only artifact-consistency checker for bureau run dirs.
#
# Usage:  scripts/preflight-artifacts.sh <RUN_DIR> [--phase round1|final]
#
# Exit codes:
#   0  all checks passed (stdout: "preflight: clean")
#   1  one or more defects found (stdout: one report line per defect,
#      format: <file>:<approx-line> — <check-id> — <detail>)
#   2  cannot run — bad args, RUN_DIR missing or unreadable (stderr: error)
#
# Distinct from scripts/preflight.sh (that checks env keys and writes
# preflight.md). This script is read-only: it writes nothing, creates no temp
# files inside RUN_DIR, and mutates nothing in the checked run dir.
#
# Bash 3.2 / macOS: no declare -A, no readarray/mapfile, no flock,
# no set -e with bare grep calls; grep -F for literal-$ patterns;
# grep -Fxq for set-membership tests.

PHASE="round1"
RUN_DIR=""

# ── Argument parsing ─────────────────────────────────────────────────────────

while [ $# -gt 0 ]; do
  case "$1" in
    --phase)
      if [ $# -lt 2 ]; then
        echo "preflight: --phase requires an argument" >&2
        exit 2
      fi
      shift
      case "$1" in
        round1|final) PHASE="$1" ;;
        *) echo "preflight: unknown phase '$1'; expected round1 or final" >&2; exit 2 ;;
      esac
      ;;
    --*)
      echo "preflight: unknown option: $1" >&2
      exit 2
      ;;
    *)
      if [ -n "$RUN_DIR" ]; then
        echo "preflight: unexpected argument: $1" >&2
        exit 2
      fi
      RUN_DIR="$1"
      ;;
  esac
  shift
done

if [ -z "$RUN_DIR" ]; then
  cat >&2 <<'USAGE'
Usage: scripts/preflight-artifacts.sh <RUN_DIR> [--phase round1|final]

  <RUN_DIR>   absolute path to a bureau run dir (required)
  --phase     round1 (default, pre-Challenger) or final (close-out)

Exit codes:
  0  all checks passed
  1  defects found (one report line per defect: file:line — check-id — detail)
  2  cannot run (bad args or RUN_DIR missing/unreadable)
USAGE
  exit 2
fi

if [ ! -d "$RUN_DIR" ]; then
  echo "preflight: RUN_DIR not found or not a directory: $RUN_DIR" >&2
  exit 2
fi

# ── Setup ────────────────────────────────────────────────────────────────────

SPEC="$RUN_DIR/spec.md"
PLAN="$RUN_DIR/plan.md"
PROMPTS="$RUN_DIR/prompts.md"

# Temp work area — never inside RUN_DIR (read-only guarantee)
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

DEFECTS="$WORK/defects.txt"
DEFS="$WORK/defs.txt"
> "$DEFECTS"
> "$DEFS"

add_defect() {
  printf '%s\n' "$1" >> "$DEFECTS"
}

# ── (a) Presence ─────────────────────────────────────────────────────────────
# round1: spec.md + plan.md required; prompts.md absence is expected, not flagged.
# final:  spec.md + plan.md + prompts.md all required.

MISSING_SPEC=0
MISSING_PLAN=0

if [ ! -f "$SPEC" ]; then
  add_defect "spec.md:0 — presence — required artifact absent: spec.md"
  MISSING_SPEC=1
fi
if [ ! -f "$PLAN" ]; then
  add_defect "plan.md:0 — presence — required artifact absent: plan.md"
  MISSING_PLAN=1
fi
if [ "$PHASE" = "final" ] && [ ! -f "$PROMPTS" ]; then
  add_defect "prompts.md:0 — presence — required artifact absent: prompts.md"
fi

# Without spec + plan the remaining checks cannot run meaningfully
if [ "$MISSING_SPEC" -eq 1 ] || [ "$MISSING_PLAN" -eq 1 ]; then
  cat "$DEFECTS"
  exit 1
fi

# ── Harvest definitions ───────────────────────────────────────────────────────
# Collect all defined IDs from spec.md and any local defs from plan.md.
#
# Definition line: after optional whitespace —
#   Bold form:    **FR N  /  **EC N  /  **AC N
#   Heading form: # FR N  /  ## EC N  /  ... (1–6 hashes)
#
# Membership set is a sorted, deduplicated newline-delimited list.
# Test with: grep -Fxq "$candidate" "$DEFS"

harvest_defs() {
  local f="$1"
  [ -f "$f" ] || return
  # Bold form: optional leading whitespace, then **, then TYPE + space + digits
  grep -E '^[[:space:]]*\*\*(FR|EC|AC) [0-9]+' "$f" | \
    sed -E 's/^[[:space:]]*\*\*(FR|EC|AC) ([0-9]+).*/\1 \2/' >> "$DEFS"
  # Heading form: optional leading whitespace, then 1–6 hashes + space + TYPE + space + digits
  grep -E '^[[:space:]]*#{1,6} (FR|EC|AC) [0-9]+' "$f" | \
    sed -E 's/^[[:space:]]*#{1,6} (FR|EC|AC) ([0-9]+).*/\1 \2/' >> "$DEFS"
}

harvest_defs "$SPEC"
harvest_defs "$PLAN"
sort -u "$DEFS" -o "$DEFS"

# ── (c) FR coverage ───────────────────────────────────────────────────────────
# Every FR N defined in spec.md must appear by ID at least once in plan.md.
# Prose-only coverage is not checked (ID-form mentions only).
# Checked at both round1 and final.

FR_DEFS="$WORK/fr_defs.txt"
> "$FR_DEFS"
grep -E '^[[:space:]]*\*\*FR [0-9]+' "$SPEC" | \
  sed -E 's/^[[:space:]]*\*\*FR ([0-9]+).*/FR \1/' >> "$FR_DEFS"
grep -E '^[[:space:]]*#{1,6} FR [0-9]+' "$SPEC" | \
  sed -E 's/^[[:space:]]*#{1,6} FR ([0-9]+).*/FR \1/' >> "$FR_DEFS"
sort -u "$FR_DEFS" -o "$FR_DEFS"

fr_id=""
while IFS= read -r fr_id || [ -n "$fr_id" ]; do
  [ -n "$fr_id" ] || continue
  fr_num="${fr_id#FR }"
  # Whole-token match: not preceded by alphanumeric, not followed by alphanumeric
  # This prevents "FR 1" from matching "FR 10" and correctly skips "FR-1" (no space)
  if ! grep -qE "(^|[^[:alnum:]])FR ${fr_num}([^[:alnum:]]|$)" "$PLAN"; then
    add_defect "plan.md:0 — fr-coverage — ${fr_id} defined in spec.md but not cited by ID in plan.md"
  fi
done < "$FR_DEFS"

# ── (b) Dangling ID refs ──────────────────────────────────────────────────────
# Every space-form FR N / EC N / AC N token in plan.md (and prompts.md at final)
# must resolve to a definition harvested from spec.md (or a local plan.md def).
#
# The hyphen form (FR-N, EC-N, AC-N) is the opt-out: never extracted, never flagged.
# Inline single-backtick spans are NOT stripped — a token inside `code` in a
# scanned file is treated as a reference.
#
# spec.md's own body is never scanned (avoids cross-artifact false positives).

TOK="$WORK/toks.txt"

check_dangling() {
  local f="$1"
  local fname
  fname="$(basename "$f")"
  local n=0
  local line tok
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n+1))
    # Extract all space-form ID tokens from this line
    > "$TOK"
    printf '%s\n' "$line" | grep -oE '(FR|EC|AC) [0-9]+' >> "$TOK" 2>/dev/null || true
    while IFS= read -r tok || [ -n "$tok" ]; do
      [ -n "$tok" ] || continue
      if ! grep -Fxq "$tok" "$DEFS"; then
        add_defect "${fname}:${n} — dangling-ref — ${tok} is not defined in spec.md; if this is a cross-artifact reference, hyphenate it (FR-17) or use prose"
      fi
    done < "$TOK"
  done < "$f"
}

check_dangling "$PLAN"
if [ "$PHASE" = "final" ] && [ -f "$PROMPTS" ]; then
  check_dangling "$PROMPTS"
fi

# ── (d) Snippet invariants ────────────────────────────────────────────────────
# Inside triple-backtick fenced blocks only, flag four forbidden patterns.
# Inline single-backtick spans are not scanned.
#
# Forbidden patterns (check d):
#   jq-lone-dot        — jq -e . (lone-dot filter; exits on truthiness, not parse-success)
#   advisory-lock-call — flock (unavailable on macOS Bash 3.2)
#   array-builtin-call — readarray (Bash 4+ builtin)
#   array-builtin-call — mapfile (Bash 4+ builtin)
#
# round1: spec.md + plan.md
# final:  spec.md + plan.md + prompts.md

check_snippets() {
  local f="$1"
  local fname
  fname="$(basename "$f")"
  local n=0
  local in_fence=0
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n+1))
    # Toggle fenced-block state when first non-whitespace chars are ```
    if printf '%s\n' "$line" | grep -qE '^[[:space:]]*```'; then
      if [ "$in_fence" -eq 0 ]; then
        in_fence=1
      else
        in_fence=0
      fi
      continue
    fi
    [ "$in_fence" -eq 1 ] || continue

    # 1. jq-lone-dot: jq -e . where . is a lone-dot filter
    #    (dot immediately followed by whitespace or end-of-line, not a selector like .foo)
    if printf '%s\n' "$line" | grep -qE 'jq[[:space:]]+-e[[:space:]]+\.([[:space:]]|$)'; then
      add_defect "${fname}:${n} — jq-lone-dot — bare 'jq -e .' gate exits on truthiness not parse-success; use 'jq -e type == \"object\"' or similar"
    fi

    # 2. advisory-lock-call: flock (unavailable on macOS Bash 3.2)
    if printf '%s\n' "$line" | grep -qF 'flock'; then
      add_defect "${fname}:${n} — advisory-lock-call — flock is unavailable on macOS Bash 3.2"
    fi

    # 3. array-builtin-call: readarray (Bash 4+ only)
    if printf '%s\n' "$line" | grep -qF 'readarray'; then
      add_defect "${fname}:${n} — array-builtin-call — readarray is a Bash 4+ builtin; macOS ships Bash 3.2"
    fi

    # 4. array-builtin-call: mapfile (Bash 4+ only)
    if printf '%s\n' "$line" | grep -qF 'mapfile'; then
      add_defect "${fname}:${n} — array-builtin-call — mapfile is a Bash 4+ builtin; macOS ships Bash 3.2"
    fi

  done < "$f"
}

check_snippets "$SPEC"
check_snippets "$PLAN"
if [ "$PHASE" = "final" ] && [ -f "$PROMPTS" ]; then
  check_snippets "$PROMPTS"
fi

# ── (e) AC coverage (--phase final only) ─────────────────────────────────────
# Every AC N defined in spec.md must be cited by ID in plan.md or prompts.md.
# This is the scripted half of the FR 7a completion-checklist AC-coverage check.

if [ "$PHASE" = "final" ]; then
  AC_DEFS="$WORK/ac_defs.txt"
  > "$AC_DEFS"
  grep -E '^[[:space:]]*\*\*AC [0-9]+' "$SPEC" | \
    sed -E 's/^[[:space:]]*\*\*AC ([0-9]+).*/AC \1/' >> "$AC_DEFS"
  grep -E '^[[:space:]]*#{1,6} AC [0-9]+' "$SPEC" | \
    sed -E 's/^[[:space:]]*#{1,6} AC ([0-9]+).*/AC \1/' >> "$AC_DEFS"
  sort -u "$AC_DEFS" -o "$AC_DEFS"

  ac_id=""
  ac_num=""
  plan_ok=0
  prompts_ok=0
  while IFS= read -r ac_id || [ -n "$ac_id" ]; do
    [ -n "$ac_id" ] || continue
    ac_num="${ac_id#AC }"
    plan_ok=0
    prompts_ok=0
    if grep -qE "(^|[^[:alnum:]])AC ${ac_num}([^[:alnum:]]|$)" "$PLAN"; then
      plan_ok=1
    fi
    if [ -f "$PROMPTS" ] && grep -qE "(^|[^[:alnum:]])AC ${ac_num}([^[:alnum:]]|$)" "$PROMPTS"; then
      prompts_ok=1
    fi
    if [ "$plan_ok" -eq 0 ] && [ "$prompts_ok" -eq 0 ]; then
      add_defect "spec.md:0 — ac-coverage — ${ac_id} defined in spec.md but not cited by ID in plan.md or prompts.md"
    fi
  done < "$AC_DEFS"
fi

# ── Output ────────────────────────────────────────────────────────────────────

if [ -s "$DEFECTS" ]; then
  cat "$DEFECTS"
  exit 1
fi

echo "preflight: clean"
exit 0
