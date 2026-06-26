name: F07 · revise-cap.sh under-cap emits "revise" and increments the counter
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  SC="$ROOT/scripts/revise-cap.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  printf '{"topology":"integrated","revise_counts":{"02":0},"revision_cap":2}\n' > "$TMP/ds.json"
  OUT=$(sh "$SC" "$TMP/ds.json" 02 2)
  [ "$OUT" = "revise" ]
  jq -e '.revise_counts["02"]==1' "$TMP/ds.json"
expected: exit 0 — stdout is exactly "revise" and revise_counts["02"] becomes 1 after one increment (start 0, cap 2). Nonzero if the increment is removed (count stays 0) or the cap fires early ("escalate").
phase: 03 · execute-plan (Delegate v2)
owner: prompts.md Prompt 3 (scripts/revise-cap.sh)
