name: preflight --env-file — docker/remote-secret repos pass on key presence in a named .env, absent keys still fail, host-shell mode unchanged
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  PF="$ROOT/scripts/preflight.sh"
  TMPF=$(mktemp -d)
  FIX="$TMPF/proj"; RUN="$TMPF/run"
  mkdir -p "$FIX" "$RUN"
  # .env.example names three keys (values are placeholders, never read as values).
  printf '%s\n' \
    'DATABASE_URL=your-key-here' \
    'JWT_SECRET_KEY=your-key-here' \
    'STRIPE_SECRET_KEY=your-key-here' \
    > "$FIX/.env.example"

  # (a) PRE-FIX RED path: no --env-file, keys absent from the invoking shell → FAIL exit 1.
  # `env -i` guarantees an empty environment so no key can accidentally be present.
  env -i bash "$PF" "$FIX" "$RUN" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 1 ] || { echo "expected exit 1 (host-shell FAIL), got $rc"; rm -rf "$TMPF"; exit 1; }
  grep -q '^- result: FAIL' "$RUN/preflight.md" || { echo "expected result: FAIL"; rm -rf "$TMPF"; exit 1; }

  # (b) POST-FIX GREEN path: a synthetic .env carrying all three keys (docker-style;
  # one uses `export`, dummy secret values that must NOT be read) → PASS exit 0.
  printf '%s\n' \
    'DATABASE_URL=postgres://user:secret@db/app' \
    'export JWT_SECRET_KEY=super-secret-signing-key' \
    'STRIPE_SECRET_KEY=sk_live_deadbeef' \
    > "$FIX/.env"
  env -i bash "$PF" "$FIX" "$RUN" --env-file "$FIX/.env" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 0 ] || { echo "expected exit 0 (--env-file PASS), got $rc"; rm -rf "$TMPF"; exit 1; }
  grep -q '^- result: PASS' "$RUN/preflight.md" || { echo "expected result: PASS"; rm -rf "$TMPF"; exit 1; }
  # Secret-safe: no value from the .env may appear in preflight.md.
  if grep -Eqi 'postgres://|super-secret|sk_live_' "$RUN/preflight.md"; then
    echo "SECRET LEAK: a value from .env reached preflight.md"; rm -rf "$TMPF"; exit 1
  fi

  # (c) A key present in .env.example but ABSENT from the .env still FAILs under --env-file.
  printf '%s\n' \
    'DATABASE_URL=postgres://user:secret@db/app' \
    'JWT_SECRET_KEY=super-secret-signing-key' \
    > "$FIX/.env.partial"
  env -i bash "$PF" "$FIX" "$RUN" --env-file "$FIX/.env.partial" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 1 ] || { echo "expected exit 1 (missing key under --env-file), got $rc"; rm -rf "$TMPF"; exit 1; }
  grep -q '^- result: FAIL' "$RUN/preflight.md" || { echo "expected result: FAIL (missing STRIPE_SECRET_KEY)"; rm -rf "$TMPF"; exit 1; }
  grep -q 'STRIPE_SECRET_KEY' "$RUN/preflight.md" || { echo "expected STRIPE_SECRET_KEY in fail table"; rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo "PASS"
  # Mutation: delete the `if [[ -n "$ENV_FILE" ]]; then ... env_file_has_key ...`
  # branch in the validate loop and path (b) falls back to the host-shell check —
  # all three keys FAIL exit 1, so the (b) PASS assertion fails and this fixture goes RED.
expected: exit 0; stdout "PASS"; host-shell mode FAILs exit 1, --env-file mode PASSes exit 0 on key presence, absent key FAILs exit 1, no secret value in preflight.md
phase: bug-fix · build-tail-tooling-fixes
owner: Bug 1 / scripts/preflight.sh --env-file flag
