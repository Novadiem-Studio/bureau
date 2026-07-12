name: audit-r2 F2/F3 no-false-fire — a legit non-zero role block with NO _note stays "exact" and byte-identical to the pre-fix output
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); trap 'rm -rf "$TMPF"' EXIT
  RP="$TMPF/clean"; mkdir -p "$RP"; echo '{}' > "$RP/state.json"

  # A clean multi-role run: real non-zero tokens, no event carries a _note. The
  # confidence downgrade and note-fold must NOT fire — the blocks stay "exact" and
  # the WHOLE output is byte-identical to what account-tokens.sh produced before the
  # audit-r2 change. This is the guard that the zero-with-note downgrade is narrow.
  printf '%s\n' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"c1","at":"2026-07-11T00:01:00Z","turns":5,"tokens":{"input":100,"cache_creation":50,"cache_read":25,"processed":175,"output":10},"final":true}' \
    'DELEGATE-TOKEN-EVENT: {"session_id":"d1","at":"2026-07-11T00:02:00Z","turns":3,"tokens":{"input":40,"cache_creation":20,"cache_read":10,"processed":70,"output":8},"final":true}' \
    'REVIEWER-TOKEN-EVENT: {"checkpoint":"05","at":"2026-07-11T00:03:00Z","turns":2,"tokens":{"input":30,"cache_creation":15,"cache_read":5,"processed":50,"output":6},"spawn_id":"05-1"}' \
    > "$RP/log.md"

  out=$(bash "$ROOT/scripts/account-tokens.sh" "$RP") || { echo "FAIL: account-tokens exited nonzero"; exit 1; }

  # All three role blocks stay "exact" and carry NO _note key.
  echo "$out" | jq -e '
    .conductor_tokens.confidence == "exact" and (.conductor_tokens | has("_note") | not) and
    .delegate_tokens.confidence  == "exact" and (.delegate_tokens  | has("_note") | not) and
    .reviewer_tokens.confidence  == "exact" and (.reviewer_tokens  | has("_note") | not)
  ' > /dev/null || { echo "FAIL: a clean block was perturbed: $(echo "$out" | jq -c '{c:.conductor_tokens,d:.delegate_tokens,r:.reviewer_tokens}')"; exit 1; }

  # Byte-identical to the pre-fix (main) script's output on the same input — the
  # strongest no-false-fire guard: nothing about a clean run changed.
  git show main:scripts/account-tokens.sh > "$TMPF/old.sh"
  old=$(bash "$TMPF/old.sh" "$RP" | jq -cS .)
  new=$(echo "$out" | jq -cS .)
  if [ "$old" != "$new" ]; then
    echo "FAIL: output differs from pre-fix on a clean run"
    printf '%s\n' "$old" > "$TMPF/old.json"; printf '%s\n' "$new" > "$TMPF/new.json"
    diff "$TMPF/old.json" "$TMPF/new.json"
    exit 1
  fi

  echo "PASS"
  # Mutation note: this input has no _note on any event, so the fix must be a strict
  # no-op here. If the note-fold were made unconditional (e.g. always add an empty
  # {_note:""} to each block) the `has("_note") | not` assertions and the byte-identity
  # diff both fail. The fix only adds behaviour on the zero-with-note path; on a clean
  # non-zero corpus the output must be byte-for-byte the pre-fix output.
expected: exit 0; stdout "PASS"; a clean non-zero multi-role run keeps all three blocks "exact" with no _note, and the full output is byte-identical to the pre-fix script — the zero-with-note downgrade does not false-fire on real data.
phase: 04 · feature — audit round 2, Findings 2+3 no-false-fire guard
owner: account-tokens.sh zero-with-note downgrade narrowness (no perturbation of clean blocks)
