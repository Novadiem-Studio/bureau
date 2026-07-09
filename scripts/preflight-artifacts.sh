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
#
# grep pinned to the system binary: a PATH grep may be ugrep, which does not
# match the (^|[^[:alnum:]]) boundary-group idiom these checks depend on
# (eval ledger 2026-07-06 — 28 false defects on the B16 run).
PATH="/usr/bin:$PATH"

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

# ── Helper: read target_repo from state.json ──────────────────────────────────
# Reads RUN_DIR/state.json, returns the absolute path via stdout.
# Returns empty string if the value is "(no-target)", file is missing, or
# unreadable. Never exits the script on failure — degrades cleanly.

read_target_repo() {
  local json="$RUN_DIR/state.json"
  [ -f "$json" ] || return
  local val
  val=$(grep '"target_repo"' "$json" | sed 's/.*"target_repo"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  [ "$val" = "(no-target)" ] && return
  printf '%s' "$val"
}

# ── (h) Convention citations ──────────────────────────────────────────────────
# Scans non-fenced, non-heading, non-ID-definition lines for a compound
# structural term from the closed keyword set immediately adjacent to a
# backticked concrete name.  When triggered, requires a citation on the same
# line OR the immediately following line:
#   CLAUDE.md §         — on-disk resolved against target_repo
#   novadiem-engineering § — always valid, no on-disk resolve
#   no CLAUDE.md for    — explicit no-CLAUDE.md escape (EC 4)
# Missing citation → convention-uncited
# CLAUDE.md § citation with missing file/heading → convention-source-missing
#
# Bash 3.2 / BSD grep portable; uses pinned PATH from line 24.

check_convention_citations() {
  local f="$1"
  local fname
  fname="$(basename "$f")"
  local target_repo_val
  target_repo_val="$(read_target_repo)"

  # Use awk for the main line-scanning loop (performance: ~200× faster than
  # per-line grep/sed subshells on multi-hundred-line specs).
  #
  # Awk emits one output line per finding in one of two forms:
  #   UNCITED:<lineno>:<triggered line (first 60 chars)>
  #   CITED:<lineno>:<path token before §>:<heading after §>
  #
  # The shell then converts each form to an add_defect call, and resolves
  # CITED on-disk (CLAUDE.md § only; novadiem-engineering § and no CLAUDE.MD
  # for are treated as valid without on-disk resolve).
  local awk_out
  awk_out="$(awk '
  function strip_dbtick(s,   r) {
    # Remove double-backtick markdown spans (may contain inner single backticks).
    # Iterative match removes each span from left to right.
    r = s
    while (match(r, /``[^`]*(`[^`]*`)*[^`]*``/)) {
      r = substr(r, 1, RSTART-1) substr(r, RSTART+RLENGTH)
    }
    return r
  }
  function has_citation(s) {
    return (s ~ /CLAUDE\.md §/ || s ~ /novadiem-engineering §/ || s ~ /no CLAUDE\.md for/)
  }
  function is_claude_cite(s) {
    return (s ~ /CLAUDE\.md §/ && s !~ /novadiem-engineering §/ && s !~ /no CLAUDE\.md for/)
  }
  function extract_cited_path(s,   tok, rest) {
    # Token immediately before §: last whitespace-delimited token preceding §
    rest = s
    while (match(rest, /[^[:space:]]+[[:space:]]+§/)) {
      tok = substr(rest, RSTART, RLENGTH)
      sub(/[[:space:]]+§.*/, "", tok)
      rest = substr(rest, RSTART+RLENGTH)
    }
    return tok
  }
  function extract_cited_heading(s,   parts, h) {
    # split() matches the full 2-byte UTF-8 sequence for §, so parts[2] starts
    # at the byte immediately after the closing byte of §.  index()+substr()
    # with +1 lands inside the 2-byte sequence and prepends a stray 0xA7 byte.
    if (split(s, parts, "§") < 2) return ""
    h = parts[2]
    sub(/^[[:space:]]+/, "", h)
    # Strip trailing sentence punctuation that may follow the heading in prose
    # (e.g. "CLAUDE.md § Store slice conventions." — the period is sentence-end,
    # not part of the heading title).
    sub(/[[:space:].,);:]+$/, "", h)
    return h
  }
  BEGIN { in_fence = 0; prev_triggered = 0; prev_line = ""; prev_n = 0 }
  {
    n++
    line = $0

    # Handle deferred citation check from previous triggered line
    if (prev_triggered) {
      if (has_citation(line)) {
        if (is_claude_cite(line)) {
          p = extract_cited_path(line)
          h = extract_cited_heading(line)
          if (p != "") print "CITED:" prev_n ":" p ":" h
        }
        # else novadiem-engineering § or no CLAUDE.MD for — valid, no output
      } else {
        print "UNCITED:" prev_n ":" substr(prev_line, 1, 60)
      }
      prev_triggered = 0
    }

    # Toggle fenced-block state
    if (line ~ /^[[:space:]]*```/) { in_fence = !in_fence; next }
    if (in_fence) next

    # Skip heading lines and ID-definition lines
    if (line ~ /^[[:space:]]*#/) next
    if (line ~ /^[[:space:]]*\*\*(FR|EC|AC)/) next

    # Strip double-backtick spans for trigger check only
    scan = strip_dbtick(line)

    # Check adjacency trigger (combined ERE alternation for all 10 terms)
    TERMS = "(store slice|service class|error envelope|response envelope|db column|database column|sql table|db table|database table|saga)"
    triggered = 0
    if (scan ~ ("`[^`]+`[[:space:]]+" TERMS)) triggered = 1
    if (!triggered && scan ~ (TERMS "[[:space:]]+(named[[:space:]]+|called[[:space:]]+)?`[^`]+")) triggered = 1

    if (triggered) {
      if (has_citation(line)) {
        if (is_claude_cite(line)) {
          p = extract_cited_path(line)
          h = extract_cited_heading(line)
          if (p != "") print "CITED:" n ":" p ":" h
        }
      } else {
        prev_triggered = 1
        prev_line = line
        prev_n = n
      }
    }
  }
  END {
    if (prev_triggered) print "UNCITED:" prev_n ":" substr(prev_line, 1, 60)
  }
  ' "$f")"

  # Process awk output: emit add_defect calls for each finding
  local emit_line emit_type emit_n emit_detail emit_path emit_heading
  local resolved_file
  while IFS= read -r emit_line || [ -n "$emit_line" ]; do
    [ -n "$emit_line" ] || continue
    emit_type="${emit_line%%:*}"
    rest="${emit_line#*:}"
    emit_n="${rest%%:*}"
    emit_detail="${rest#*:}"

    case "$emit_type" in
      UNCITED)
        add_defect "${fname}:${emit_n} — convention-uncited — ${emit_detail}"
        ;;
      CITED)
        # On-disk resolve for CLAUDE.md § citations
        emit_path="${emit_detail%%:*}"
        emit_heading="${emit_detail#*:}"
        if [ -n "$target_repo_val" ]; then
          resolved_file="${target_repo_val}/${emit_path}"
          if [ ! -f "$resolved_file" ] || ! grep -qF "$emit_heading" "$resolved_file" 2>/dev/null; then
            add_defect "${fname}:${emit_n} — convention-source-missing — ${emit_path}"
          fi
        fi
        # If target_repo_val is empty (no-target / self-run): treat as valid (R3 degrade path)
        ;;
    esac
  done << EOF
$awk_out
EOF
}

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
#   jq-lone-dot        — jq -e . and equivalent spellings: unquoted/quoted lone dot
#                         ('.' or "."), combined-letter flags like -er, --exit-status.
#                         NOT matched: split-flag sequences where e is not in the lead
#                         position (e.g. -r -e .) and glued flags without spaces (e.g.
#                         -e-r); lone-dot only — jq -e '.foo' is safe.
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

    # 1. jq-lone-dot: lone-dot filter with exit-status semantics, all spellings.
    #    Flags matched: -e, -er, -re (e-in-lead-position clusters), --exit-status. NOT matched: split-flag sequences (-r -e) and glued -e-r.
    #    Filter forms: . (unquoted), '.' (single-quoted), "." (double-quoted).
    #    A quoted lone dot is never a legitimate filter; no false-positive risk.
    #    A real filter like jq -e '.foo' does NOT match (not a lone dot after the flag).
    jq_lone_dot=0
    # Unquoted lone dot: jq -e . | jq -er . | jq -e -r . | jq --exit-status . etc.
    if printf '%s\n' "$line" | grep -qE 'jq[[:space:]]+(-e[[:alnum:]]*|-[[:alnum:]]*e[[:alnum:]]*|--exit-status)([[:space:]]+-[[:alnum:]-]+)*[[:space:]]+\.([[:space:]]|$)'; then
      jq_lone_dot=1
    fi
    # Single-quoted lone dot: jq -e '.' | jq -er '.' | jq --exit-status '.' etc.
    if printf '%s\n' "$line" | grep -qE "jq[[:space:]]+(-e[[:alnum:]]*|-[[:alnum:]]*e[[:alnum:]]*|--exit-status)([[:space:]]+-[[:alnum:]-]+)*[[:space:]]+'\\.'"; then
      jq_lone_dot=1
    fi
    # Double-quoted lone dot: jq -e "." | jq -er "." | jq --exit-status "." etc.
    # _dq_jq_pat ends with the opening " of the filter; \\.\" appends literal-dot + closing "
    _dq_jq_pat='jq[[:space:]]+(-e[[:alnum:]]*|-[[:alnum:]]*e[[:alnum:]]*|--exit-status)([[:space:]]+-[[:alnum:]-]+)*[[:space:]]+"'
    if printf '%s\n' "$line" | grep -qE "${_dq_jq_pat}\\.\""; then
      jq_lone_dot=1
    fi
    if [ "$jq_lone_dot" -eq 1 ]; then
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

# ── (h) Convention citations ──────────────────────────────────────────────────
# round1: spec.md + plan.md; also harmless at final.

if [ "$PHASE" = "round1" ] || [ "$PHASE" = "final" ]; then
  check_convention_citations "$SPEC"
  check_convention_citations "$PLAN"
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
