name: account-run — bad args: no-arg exits non-zero with "exactly one argument required"; relative path exits non-zero with "must be an absolute path"
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  # sub-case A: no arg
  out_noarg=$(bash "$ROOT/scripts/account-run.sh" 2>&1) && { exit 1; }
  printf '%s\n' "$out_noarg" | grep -q 'exactly one argument required' || exit 1
  # sub-case B: relative path
  out_rel=$(bash "$ROOT/scripts/account-run.sh" relative/path 2>&1) && { exit 1; }
  printf '%s\n' "$out_rel" | grep -q 'must be an absolute path' || exit 1
  echo "PASS"
expected: exit 0; stdout "PASS"; no-arg exits non-zero with "exactly one argument required"; relative path exits non-zero with "must be an absolute path"
phase: 01 · execute-plan
owner: Prompt 01 / account-run base-engine battle-test
