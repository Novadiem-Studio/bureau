#!/usr/bin/env bash
# Validate .env.example keys against the live environment.
#
# Usage:
#   ./scripts/preflight.sh <target-dir> <RUN_DIR>
#
# Arguments:
#   <target-dir>   project directory that may contain .env.example
#   <RUN_DIR>      absolute path to the run directory; preflight.md is written here
#
# Exit codes:
#   0  all keys pass (or nothing to validate)
#   1  one or more keys are missing / empty / placeholder, or bad arguments

set -euo pipefail

usage() {
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

die() { echo "preflight: $*" >&2; exit 1; }

# ── argument handling ────────────────────────────────────────────────────────

[[ $# -eq 2 ]] || usage 1

TARGET_DIR="$1"
RUN_DIR="$2"

# Resolve RUN_DIR first — it must exist before we do any work
[[ -d "$RUN_DIR" ]] || die "RUN_DIR does not exist: $RUN_DIR"

# Resolve target-dir to absolute path (may or may not exist — we handle missing below)
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd || true)"
[[ -n "$TARGET_DIR" ]] || die "target-dir does not exist or is not a directory: $1"

EXAMPLE_FILE="$TARGET_DIR/.env.example"
PREFLIGHT_MD="$RUN_DIR/preflight.md"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ── case: no .env.example ────────────────────────────────────────────────────

if [[ ! -f "$EXAMPLE_FILE" ]]; then
  echo "preflight: no .env.example found — nothing to validate"
  tmp="$(mktemp "${TMPDIR:-/tmp}/preflight.XXXXXX")"
  cat >"$tmp" <<EOF
# Preflight — PASS

- timestamp: $TIMESTAMP
- result: PASS
- target_dir: $TARGET_DIR
- vars_checked: 0
- note: no .env.example
EOF
  mv "$tmp" "$PREFLIGHT_MD"
  exit 0
fi

# ── parse keys from .env.example ─────────────────────────────────────────────

# Read non-comment, non-blank lines; strip optional leading "export "; take LHS of first =
keys=()
while IFS= read -r line; do
  # skip blank / whitespace-only lines
  [[ "$line" =~ ^[[:space:]]*$ ]] && continue
  # skip comment lines (# may be preceded by whitespace)
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  # strip optional leading "export "
  line="${line#export }"
  # extract key name: everything up to (but not including) the first =
  key="${line%%=*}"
  # skip if key is empty (malformed line with no =)
  [[ -n "$key" ]] && keys+=("$key")
done <"$EXAMPLE_FILE"

# ── case: file present but zero keys ─────────────────────────────────────────

if [[ ${#keys[@]} -eq 0 ]]; then
  echo "preflight: OK — 0 vars checked"
  tmp="$(mktemp "${TMPDIR:-/tmp}/preflight.XXXXXX")"
  cat >"$tmp" <<EOF
# Preflight — PASS

- timestamp: $TIMESTAMP
- result: PASS
- target_dir: $TARGET_DIR
- vars_checked: 0
EOF
  mv "$tmp" "$PREFLIGHT_MD"
  exit 0
fi

# ── validate each key ─────────────────────────────────────────────────────────

fail_keys=()
fail_reasons=()
fail_values=()  # will hold display value (masked or empty) per failed key
pass_count=0

is_placeholder() {
  local v="$1"
  # Lowercase the value for case-insensitive matching
  local lv
  lv="$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]')"
  case "$lv" in
    your-key-here|your_key_here|changeme|change_me|change-me|\
    placeholder|example|insert-here|todo|fixme)
      return 0 ;;
  esac
  # Glob-style patterns: starts with <your_ or <insert_
  [[ "$lv" == '<your_'*  ]] && return 0
  [[ "$lv" == '<insert_'* ]] && return 0
  return 1
}

for key in "${keys[@]}"; do
  # nounset-safe: ${!key-} gives "" for both unset and set-to-empty; safe under set -u
  # Use ${!key+set} to distinguish: empty string = unset; "set" = present (even if empty value)
  presence="${!key+set}"
  val="${!key-}"

  if [[ -z "$presence" ]]; then
    # Key is not present in the environment at all
    fail_keys+=("$key")
    fail_reasons+=("missing")
    fail_values+=("")
    echo "preflight: FAIL  $key  missing"
  elif [[ -z "$val" ]]; then
    # Key is present but set to empty string
    fail_keys+=("$key")
    fail_reasons+=("empty")
    fail_values+=("")
    echo "preflight: FAIL  $key  empty"
  elif is_placeholder "$val"; then
    # Key is present, non-empty, but matches a placeholder pattern
    fail_keys+=("$key")
    fail_reasons+=("placeholder")
    fail_values+=("[placeholder detected]")
    echo "preflight: FAIL  $key  placeholder  [placeholder detected]"
  else
    (( pass_count++ )) || true
  fi
done

# ── write preflight.md (always, pass or fail) ─────────────────────────────────

result="PASS"
[[ ${#fail_keys[@]} -eq 0 ]] || result="FAIL"

tmp="$(mktemp "${TMPDIR:-/tmp}/preflight.XXXXXX")"
{
  echo "# Preflight — $result"
  echo ""
  echo "- timestamp: $TIMESTAMP"
  echo "- result: $result"
  echo "- target_dir: $TARGET_DIR"
  echo "- vars_checked: ${#keys[@]}"
  if [[ ${#fail_keys[@]} -gt 0 ]]; then
    echo ""
    echo "| Key | Reason | Value |"
    echo "|-----|--------|-------|"
    for i in "${!fail_keys[@]}"; do
      echo "| ${fail_keys[$i]} | ${fail_reasons[$i]} | ${fail_values[$i]} |"
    done
  fi
} >"$tmp"
mv "$tmp" "$PREFLIGHT_MD"

# ── final summary / exit ──────────────────────────────────────────────────────

if [[ ${#fail_keys[@]} -gt 0 ]]; then
  exit 1
fi

echo "preflight: OK — $pass_count vars checked"
exit 0
