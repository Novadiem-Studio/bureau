name: integration-gate.sh — an all-bare-string claimed-gates array surfaces a shape error in errors[] instead of a silent false comprehensive under_declaration (issue #74)
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/wt"; mkdir -p "$W/.bureau/regression" "$TMP/ctx"
  git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  printf '#!/bin/sh\nexit 0\n' > "$W/.bureau/regression/run.sh"
  git -C "$W" add -A; git -C "$W" commit -qm base
  BASE=$(git -C "$W" rev-parse HEAD)
  printf '{"scope":{}}\n' > "$TMP/state.json"

  # claimed-gates carries ONLY bare strings — the wrong-but-plausible shape a
  # caller might emit for a JSON array of gate names (issue #74's live signature).
  # Pre-fix, the isinstance(dict) guards in the pre-existing-red validation and the
  # under-declaration cross-check silently coerce EVERY element out, so
  # claimed_names/claimed_cmds end up empty, the "regression" canonical gate lands
  # in under_declaration, and errors[] stays [] — no diagnostic distinguishes this
  # from a real, deliberate under-declaration.
  "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates '["regression", "make lint"]' --state-json "$TMP/state.json" --out "$TMP/ctx"

  # ASSERTION 1 — under_declaration still reports "regression" (unchanged: a bare
  # string is not a valid claim per .bureau/regression/237-integration-gate-string-claimed-gate.md,
  # so this must NOT flip to empty).
  jq -e '.under_declaration | map(.name) | index("regression") != null' "$TMP/ctx/integration-results.json" \
    || { echo "FAIL: under_declaration lost the real 'regression' gate: $(jq -c '.under_declaration' "$TMP/ctx/integration-results.json")"; exit 1; }

  # ASSERTION 2 (issue #74) — errors[] now carries a non-empty diagnostic naming the
  # shape problem, so the false comprehensive under_declaration above is no longer
  # indistinguishable from a genuine one.
  err_count=$(jq '.errors | length' "$TMP/ctx/integration-results.json")
  [ "$err_count" -gt 0 ] || { echo "FAIL: errors[] is empty — bare-string claimed-gates shape problem not surfaced (issue #74): $(cat "$TMP/ctx/integration-results.json")"; exit 1; }
  jq -r '.errors[]' "$TMP/ctx/integration-results.json" | PATH=/usr/bin:$PATH grep -qi "bare" \
    || { echo "FAIL: errors[] present but does not describe the bare-string shape problem: $(jq -c '.errors' "$TMP/ctx/integration-results.json")"; exit 1; }

  echo "PASS"
expected: exit 0; stdout "PASS"; with --claimed-gates '["regression", "make lint"]' (all bare strings) against a worktree whose only canonical gate is "regression": under_declaration still names "regression" (a bare string is never a valid claim), AND errors[] is non-empty with a message describing the bare-string shape problem — never the pre-fix errors:[] silence.
phase: bug-fix · issue-74
owner: issue #74 / scripts/integration-gate.sh — PARSE claimed-gates step records a shape diagnostic in errors[] when elements are not objects
