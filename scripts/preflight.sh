#!/usr/bin/env bash
# Validate .env.example keys against the live environment (default) or a named
# .env file (--env-file, for docker/remote-secret projects whose secrets never
# reach the invoking shell).
#
# Usage:
#   ./scripts/preflight.sh <target-dir> <RUN_DIR> [--env-file <path>]
#
# Arguments:
#   <target-dir>       project directory that may contain .env.example
#   <RUN_DIR>          absolute path to the run directory; preflight.md is written here
#   --env-file <path>  check key PRESENCE in this file instead of the host shell
#                      (secret-safe: only key names on the LHS of = are read, never values)
#
# .env.example annotation:
#   # preflight: allow-empty     a comment line placed DIRECTLY above a KEY=... line
#                                 declares that key's correct value is legitimately
#                                 empty — a present-but-empty value then PASSES instead
#                                 of failing. Host-shell mode only (a key still must be
#                                 present; "missing" and "placeholder" are unaffected).
#                                 --env-file mode is presence-only and never reads
#                                 values, so this annotation has no effect there.
#
# Exit codes:
#   0  all keys pass (or nothing to validate)
#   1  one or more keys are missing / empty / placeholder, or bad arguments

set -euo pipefail

usage() {
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

die() { echo "preflight: $*" >&2; exit 1; }

# ── argument handling ────────────────────────────────────────────────────────
# Two positionals (<target-dir> <RUN_DIR>) plus an optional --env-file <path>.
# Parse in a single pass so --env-file may appear before, between, or after the
# positionals; bad flags or the wrong positional count → usage 1.

TARGET_DIR=""
RUN_DIR=""
ENV_FILE=""          # empty = host-shell check (backward compatible)
positional=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      [[ $# -ge 2 ]] || usage 1
      ENV_FILE="$2"
      shift 2
      ;;
    --env-file=*)
      ENV_FILE="${1#--env-file=}"
      shift
      ;;
    -h|--help)
      usage 0
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do positional+=("$1"); shift; done
      ;;
    -*)
      usage 1
      ;;
    *)
      positional+=("$1")
      shift
      ;;
  esac
done

[[ ${#positional[@]} -eq 2 ]] || usage 1
TARGET_DIR="${positional[0]}"
RUN_DIR="${positional[1]}"

# When --env-file is given the path must exist and be readable (secret-safe:
# key-name presence only is read below, never a value).
if [[ -n "$ENV_FILE" ]]; then
  [[ -f "$ENV_FILE" ]] || die "--env-file does not exist or is not a file: $ENV_FILE"
  [[ -r "$ENV_FILE" ]] || die "--env-file is not readable: $ENV_FILE"
fi

# Resolve RUN_DIR first — it must exist before we do any work
[[ -d "$RUN_DIR" ]] || die "RUN_DIR does not exist: $RUN_DIR"

# Resolve target-dir to absolute path (may or may not exist — we handle missing below).
# Report the ORIGINAL argument on failure: TARGET_DIR is overwritten just above, and $1 is
# unbound here (the parser consumed all positionals via shift → set -u would trap on $1).
_target_arg="${positional[0]}"
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd || true)"
[[ -n "$TARGET_DIR" ]] || die "target-dir does not exist or is not a directory: $_target_arg"

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

# Read non-comment, non-blank lines; strip optional leading "export "; take LHS of first =.
# Also track ALLOW_EMPTY_KEYS: a key whose immediately preceding non-key line (no blank
# line in between) is the exact comment `# preflight: allow-empty` opts that key's
# present-but-empty value into PASS below (a newline-delimited list, Bash-3.2-portable,
# mirroring the ENV_FILE_KEYS pattern further down).
keys=()
ALLOW_EMPTY_KEYS=""
prev_line=""
while IFS= read -r line; do
  # blank line breaks "directly above" adjacency, and is not itself a key
  if [[ "$line" =~ ^[[:space:]]*$ ]]; then
    prev_line=""
    continue
  fi
  # comment line: not a key, but remember it so the NEXT key line can check adjacency
  if [[ "$line" =~ ^[[:space:]]*# ]]; then
    prev_line="$line"
    continue
  fi
  # key line: strip optional leading "export "; extract key name (LHS of first =)
  stripped="${line#export }"
  key="${stripped%%=*}"
  if [[ -n "$key" ]]; then
    keys+=("$key")
    marker="$(printf '%s' "$prev_line" | sed -E 's/^[[:space:]]*#[[:space:]]*//')"
    [[ "$marker" == "preflight: allow-empty" ]] && ALLOW_EMPTY_KEYS="${ALLOW_EMPTY_KEYS}${key}"$'\n'
  fi
  prev_line="$line"
done <"$EXAMPLE_FILE"

# is_allow_empty_key <KEY> — returns 0 if KEY was annotated `# preflight: allow-empty`.
is_allow_empty_key() {
  local want="$1"
  local k
  while IFS= read -r k; do
    [[ "$k" == "$want" ]] && return 0
  done <<EOF
$ALLOW_EMPTY_KEYS
EOF
  return 1
}

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

# ── --env-file presence check (secret-safe) ───────────────────────────────────
# Build the set of key NAMES present in $ENV_FILE, then look each one up. Only the
# LHS of the first = on each non-comment line is read — VALUES ARE NEVER TOUCHED,
# so a secret is never loaded into a variable, echoed, or written to preflight.md.
# Same parse rules as the .env.example parser above (strip leading "export ", take
# LHS of first =). A newline-delimited list keeps this Bash 3.2 portable (no
# associative arrays).
ENV_FILE_KEYS=""
if [[ -n "$ENV_FILE" ]]; then
  while IFS= read -r efline; do
    [[ "$efline" =~ ^[[:space:]]*$ ]] && continue
    [[ "$efline" =~ ^[[:space:]]*# ]] && continue
    efline="${efline#export }"
    efkey="${efline%%=*}"
    # strip surrounding whitespace from the key name
    efkey="${efkey#"${efkey%%[![:space:]]*}"}"
    efkey="${efkey%"${efkey##*[![:space:]]}"}"
    [[ -n "$efkey" ]] && ENV_FILE_KEYS="${ENV_FILE_KEYS}${efkey}"$'\n'
  done <"$ENV_FILE"
fi

# env_file_has_key <KEY> — returns 0 if KEY appears as a key name in $ENV_FILE.
# Exact-line match against the pre-parsed newline-delimited key list (no value read).
env_file_has_key() {
  local want="$1"
  local k
  while IFS= read -r k; do
    [[ "$k" == "$want" ]] && return 0
  done <<EOF
$ENV_FILE_KEYS
EOF
  return 1
}

for key in "${keys[@]}"; do
  if [[ -n "$ENV_FILE" ]]; then
    # --env-file mode: check key-name PRESENCE in the named file (secret-safe).
    # Present as a key (LHS of =) → PASS; absent → FAIL missing. Values are never
    # read, so "empty"/"placeholder" reasons do not apply in this mode.
    if env_file_has_key "$key"; then
      (( pass_count++ )) || true
    else
      fail_keys+=("$key")
      fail_reasons+=("missing")
      fail_values+=("")
      echo "preflight: FAIL  $key  missing"
    fi
    continue
  fi

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
    # Key is present but set to empty string. PASS if .env.example annotated this key
    # `# preflight: allow-empty` (its correct value legitimately IS empty) — otherwise FAIL.
    if is_allow_empty_key "$key"; then
      (( pass_count++ )) || true
    else
      fail_keys+=("$key")
      fail_reasons+=("empty")
      fail_values+=("")
      echo "preflight: FAIL  $key  empty"
    fi
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
