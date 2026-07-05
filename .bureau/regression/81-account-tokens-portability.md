name: account-tokens portability — bash -n clean, no associative arrays / flock / GNU date
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  SCRIPT="$ROOT/scripts/account-tokens.sh"
  # Syntax check must be clean.
  bash -n "$SCRIPT" || exit 1
  # Strip comment lines before grepping so a guarantee cannot hide in a comment
  # (comment-strip authoring rule, docs/conventions/regression-fixtures.md).
  strip() { grep -v '^[[:space:]]*#' "$1"; }
  strip "$SCRIPT" | grep -q 'declare -A' && exit 1
  strip "$SCRIPT" | grep -q 'flock' && exit 1
  strip "$SCRIPT" | grep -q 'date -d' && exit 1
  strip "$SCRIPT" | grep -q 'date -j' && exit 1
  echo "PASS"
  # Mutation: introduce any of the forbidden constructs into live (non-comment)
  # code and the matching grep returns 0 -> exit 1 -> fixture fails.
expected: exit 0; stdout "PASS"; bash -n clean; no declare -A / flock / date -d / date -j in non-comment lines
phase: 04 · feature
owner: Prompt 4 / account-tokens.sh Bash 3.2 portability
