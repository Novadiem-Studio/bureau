name: account-run — bash32 portability gate: account-run.sh contains zero non-comment declare -A lines
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  count=$(grep -v '^[[:space:]]*#' "$ROOT/scripts/account-run.sh" | grep -c 'declare -A' || true)
  [ "$count" -eq 0 ] || { echo "FAIL: found $count declare -A line(s)"; exit 1; }
  echo "PASS"
expected: exit 0; stdout "PASS"; grep count of non-comment declare -A lines == 0
phase: 01 · execute-plan
owner: Prompt 01 / account-run base-engine battle-test
