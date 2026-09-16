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
# .env.example convention:
#   A key whose correct value is the empty string (e.g. a module list nothing has
#   populated yet) is declared, not silently tolerated: put a comment line reading
#   exactly "# preflight: allow-empty" directly above that key, no blank line between.
#   Without it, "present but empty" always fails (host-shell mode only — --env-file
#   mode never reads values, so this marker has no effect there). This is per-key: a
#   non-empty value on an allow-empty key is still checked for placeholder text.
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
# A comment line reading "# preflight: allow-empty" immediately above a key (no blank line
# between) declares that key's correct value CAN be the empty string — e.g. a module list
# that is deliberately empty until a phase ships. It is per-key, not a way to skip a key
# entirely: a non-empty value on an allow-empty key is still checked for placeholder text.
keys=()
ALLOW_EMPTY_KEYS=""
_pf_allow_empty_pending=0
while IFS= read -r line; do
  # skip blank / whitespace-only lines — also clears a pending marker, so it cannot leak
  # across an unrelated gap onto a later key.
  if [[ "$line" =~ ^[[:space:]]*$ ]]; then
    _pf_allow_empty_pending=0
    continue
  fi
  # comment lines (# may be preceded by whitespace): check for the marker, then skip
  if [[ "$line" =~ ^[[:space:]]*# ]]; then
    if [[ "$line" =~ ^[[:space:]]*#[[:space:]]*preflight:[[:space:]]*allow-empty[[:space:]]*$ ]]; then
      _pf_allow_empty_pending=1
    fi
    continue
  fi
  # strip optional leading "export "
  line="${line#export }"
  # extract key name: everything up to (but not including) the first =
  key="${line%%=*}"
  # skip if key is empty (malformed line with no =)
  if [[ -n "$key" ]]; then
    keys+=("$key")
    if [[ "$_pf_allow_empty_pending" -eq 1 ]]; then
      ALLOW_EMPTY_KEYS="${ALLOW_EMPTY_KEYS}${key}"$'\n'
    fi
  fi
  _pf_allow_empty_pending=0
done <"$EXAMPLE_FILE"

# key_is_allow_empty <KEY> — same shape as env_file_has_key below (Bash 3.2, no
# associative arrays): exact-line match against the pre-parsed newline-delimited list.
key_is_allow_empty() {
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
allow_empty_used=()  # keys that passed BECAUSE of an allow-empty declaration, for the report
pass_count=0

# all_keys / all_reasons: EVERY key's outcome, not just failures — see the report section
# below. rheo-stream 0c3, 2026-09-16: a report naming only failures makes "N pass" a bare,
# unaudited count on a script this run found could be made to pass for the wrong reason —
# the exact defect class the allow-empty marker itself was added to fix, one level up (a
# key silenced by the marker with no visible trace of it). Never a value, on either side —
# same secret-safety rule as fail_values above.
all_keys=()
all_reasons=()

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
      all_keys+=("$key"); all_reasons+=("pass (present in --env-file)")
    else
      fail_keys+=("$key")
      fail_reasons+=("missing")
      fail_values+=("")
      all_keys+=("$key"); all_reasons+=("FAIL: missing")
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
    all_keys+=("$key"); all_reasons+=("FAIL: missing")
    echo "preflight: FAIL  $key  missing"
  elif [[ -z "$val" ]]; then
    # Key is present but set to empty string. A declared allow-empty key (marked in
    # .env.example) treats this as its correct value, not a failure — the check couldn't
    # otherwise tell "deliberately empty" from "forgotten" (rheo-stream 0c3, 2026-09-16:
    # RHEO_MODULES' correct phase-1 value is empty, and the gate had no way to pass a
    # correct configuration — the only value that passed it was a fabricated module name).
    if key_is_allow_empty "$key"; then
      allow_empty_used+=("$key")
      (( pass_count++ )) || true
      all_keys+=("$key"); all_reasons+=("pass (declared allow-empty)")
      echo "preflight: OK    $key  empty (declared allow-empty)"
    else
      fail_keys+=("$key")
      fail_reasons+=("empty")
      fail_values+=("")
      all_keys+=("$key"); all_reasons+=("FAIL: empty")
      echo "preflight: FAIL  $key  empty"
    fi
  elif is_placeholder "$val"; then
    # Key is present, non-empty, but matches a placeholder pattern
    fail_keys+=("$key")
    fail_reasons+=("placeholder")
    fail_values+=("[placeholder detected]")
    all_keys+=("$key"); all_reasons+=("FAIL: placeholder")
    echo "preflight: FAIL  $key  placeholder  [placeholder detected]"
  else
    (( pass_count++ )) || true
    all_keys+=("$key"); all_reasons+=("pass")
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
  # Every key's outcome, not just failures (rheo-stream 0c3, 2026-09-16): "N pass" as a
  # bare count is not auditable — a reader can't see WHICH keys, or whether one of them
  # passed via a declared-allow-empty marker that deserves a second look. Never a value,
  # same rule as the failures table above.
  if [[ ${#all_keys[@]} -gt 0 ]]; then
    echo ""
    echo "All keys checked:"
    echo ""
    echo "| Key | Outcome |"
    echo "|-----|---------|"
    for i in "${!all_keys[@]}"; do
      echo "| ${all_keys[$i]} | ${all_reasons[$i]} |"
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
