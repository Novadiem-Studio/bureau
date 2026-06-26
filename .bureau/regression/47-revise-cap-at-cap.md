name: F08 · revise-cap.sh at-cap emits "escalate" and increments to the cap
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  SC="$ROOT/scripts/revise-cap.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  printf '{"topology":"integrated","revise_counts":{"02":1},"revision_cap":2}\n' > "$TMP/ds.json"
  OUT=$(sh "$SC" "$TMP/ds.json" 02 2)
  [ "$OUT" = "escalate" ]
  jq -e '.revise_counts["02"]==2' "$TMP/ds.json"
expected: exit 0 — starting count 1 with cap 2, one increment reaches 2 (>= cap), so stdout is exactly "escalate" and revise_counts["02"] becomes 2. Nonzero if the cap comparison is loosened (>= changed to >) so it prints "revise" instead.
phase: 03 · execute-plan (Delegate v2)
owner: prompts.md Prompt 3 (scripts/revise-cap.sh)
