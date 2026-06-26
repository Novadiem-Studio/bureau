name: F12 · watcher.sh passes --json-schema as inline $(cat ...) contents, NOT a bare $ROOT path, AND names the cold-reviewer task-prompt files by absolute $CTX path
command: |
  # Guards the two Prompt-7 Part-2 recipe corrections in watcher.sh against regression:
  #  (1) --json-schema takes an INLINE JSON Schema string on claude 2.1.187, not a file
  #      path; the path form aborts the spawn ("--json-schema is not valid JSON"). The
  #      recipe must inline the schema CONTENTS via $(cat "$ROOT/config/...json").
  #  (2) the cold-reviewer task prompt must name staged files by ABSOLUTE $CTX path; a
  #      bare relative name resolves against the git/workspace root and is sandbox-denied.
  # Comment-strip first (a comment mentioning the path form must not satisfy the guard),
  # and grep -F (the patterns carry a literal $).
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  W="$ROOT/scripts/watcher.sh"
  strip() { grep -v '^[[:space:]]*#' "$1"; }
  # (1a) the inline $(cat ...) form is present in live code
  strip "$W" | grep -F -q -- '--json-schema "$(cat "$ROOT/config/delegate-verdict.schema.json")"' \
    || { echo "FAIL: watcher.sh does not pass --json-schema as inline \$(cat ...) contents"; exit 1; }
  # (1b) the bare-path form is ABSENT from live code (regression guard)
  if strip "$W" | grep -F -q -- '--json-schema "$ROOT/config/delegate-verdict.schema.json"'; then
    echo "FAIL: watcher.sh still passes --json-schema as a bare \$ROOT path (regressed)"; exit 1
  fi
  # (2) the task prompt names the reviewer persona by absolute $CTX path
  strip "$W" | grep -F -q -- '${CTX}/delegate-reviewer.md' \
    || { echo "FAIL: watcher.sh task prompt does not name files by absolute \$CTX path"; exit 1; }
  echo PASS
expected: exit 0 — prints PASS: watcher.sh passes --json-schema as inline $(cat "$ROOT/config/delegate-verdict.schema.json") contents (not a bare $ROOT path), the bare-path form is absent, and the cold-reviewer task prompt names staged files by absolute ${CTX}/ path. Mutation-test: revert watcher.sh:366 to --json-schema "$ROOT/config/delegate-verdict.schema.json" → (1a) fails (inline form missing) AND (1b) fails (bare path present); revert the task prompt to bare relative names → (2) fails. Any one regression exits non-zero.
phase: 5 · execute-plan (Bundle 15 P7 build-fix) — guards the --json-schema inline + absolute-$CTX-path corrections from Prompt 7 Part 2/3
owner: prompts.md Prompt 7 build-fix (scripts/watcher.sh --json-schema inline form + absolute $CTX task-prompt paths)
