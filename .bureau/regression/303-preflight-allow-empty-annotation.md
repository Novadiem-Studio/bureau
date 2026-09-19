name: preflight.sh — `# preflight: allow-empty` lets a key's correct value legitimately be empty, without rewarding a fabricated value (issue #67)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  PF="$ROOT/scripts/preflight.sh"
  TMPF=$(mktemp -d); trap 'rm -rf "$TMPF"' EXIT
  FIX="$TMPF/proj"; RUN="$TMPF/run"
  mkdir -p "$FIX" "$RUN"

  printf '%s\n' \
    '# preflight: allow-empty' \
    'RHEO_MODULES=' \
    'PLAIN_EMPTY=' \
    > "$FIX/.env.example"

  # (a) PRE-FIX RED path, reproduced: the annotated key, present and correctly empty,
  # used to FAIL just like an unannotated empty key. Post-fix it PASSES; PLAIN_EMPTY
  # (same present-empty shape, no annotation) still FAILs — the annotation is per-key,
  # not a blanket relaxation.
  env -i RHEO_MODULES='' PLAIN_EMPTY='' bash "$PF" "$FIX" "$RUN" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 1 ] || { echo "FAIL: expected exit 1 (PLAIN_EMPTY still fails), got $rc"; exit 1; }
  grep -q '^| RHEO_MODULES ' "$RUN/preflight.md" && { echo "FAIL: annotated RHEO_MODULES appears in the fail table — annotation not honored"; exit 1; }
  grep -q '^| PLAIN_EMPTY | empty |' "$RUN/preflight.md" || { echo "FAIL: expected PLAIN_EMPTY | empty | in fail table"; cat "$RUN/preflight.md"; exit 1; }

  # (b) the gate must not reward fabrication: a bogus non-empty value for the annotated
  # key still passes (unaffected — is_placeholder doesn't match a real-looking string),
  # but the point of the fix is (a)/(c), not this — recorded for completeness of the
  # 3-way table from the issue.
  env -i RHEO_MODULES='fabricated-module' PLAIN_EMPTY='x' bash "$PF" "$FIX" "$RUN" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 0 ] || { echo "FAIL: expected exit 0 (both keys non-empty, non-placeholder), got $rc"; cat "$RUN/preflight.md"; exit 1; }

  # (c) omitted entirely (unset) still FAILs "missing" even though annotated — allow-empty
  # covers a key whose value legitimately IS empty, not a key that was never set at all.
  env -i PLAIN_EMPTY='' bash "$PF" "$FIX" "$RUN" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 1 ] || { echo "FAIL: expected exit 1 (RHEO_MODULES unset), got $rc"; exit 1; }
  grep -q '^| RHEO_MODULES | missing |' "$RUN/preflight.md" || { echo "FAIL: expected RHEO_MODULES | missing | in fail table when unset despite annotation"; cat "$RUN/preflight.md"; exit 1; }

  # (d) adjacency is literal: a blank line between the marker and the key breaks it —
  # the key is NOT annotated and a present-empty value still FAILs.
  printf '%s\n' \
    '# preflight: allow-empty' \
    '' \
    'NOT_ADJACENT=' \
    > "$FIX/.env.example"
  env -i NOT_ADJACENT='' bash "$PF" "$FIX" "$RUN" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 1 ] || { echo "FAIL: expected exit 1 (marker not directly above key), got $rc"; exit 1; }
  grep -q '^| NOT_ADJACENT | empty |' "$RUN/preflight.md" || { echo "FAIL: expected NOT_ADJACENT | empty | when marker separated by a blank line"; cat "$RUN/preflight.md"; exit 1; }

  # (e) --env-file mode is presence-only and untouched by the annotation: the key merely
  # needs to appear as a name in the file; the marker changes nothing there.
  printf '%s\n' \
    '# preflight: allow-empty' \
    'RHEO_MODULES=' \
    > "$FIX/.env.example"
  printf '%s\n' 'RHEO_MODULES=' > "$FIX/.env"
  env -i bash "$PF" "$FIX" "$RUN" --env-file "$FIX/.env" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 0 ] || { echo "FAIL: expected exit 0 (--env-file presence-only, key present), got $rc"; cat "$RUN/preflight.md"; exit 1; }

  echo "PASS"
  # Mutation: delete the `if is_allow_empty_key "$key"; then ... else` branch (collapse
  # back to the unconditional FAIL empty) in the host-shell validate loop → assertion (a)
  # RHEO_MODULES reappears in the fail table (or the whole run flips to exit 1 with both
  # keys failing) → RED. Deleting the ALLOW_EMPTY_KEYS adjacency tracking (prev_line reset
  # on blank line) instead makes assertion (d) wrongly PASS NOT_ADJACENT → RED.
expected: exit 0; stdout "PASS"; a key annotated `# preflight: allow-empty` directly above it PASSES when present-and-empty, an unannotated present-empty key still FAILs, the annotated key still FAILs "missing" when unset entirely, a blank line between the marker and the key breaks the annotation, and --env-file (presence-only) mode is unaffected.
phase: bug-fix · issue-67
owner: issue #67 / scripts/preflight.sh — per-key `# preflight: allow-empty` opt-in in .env.example
