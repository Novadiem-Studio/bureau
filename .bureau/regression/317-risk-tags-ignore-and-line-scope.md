name: risk-tags.sh ignores docs and scopes destructive-migration lines to migration files
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  S="$ROOT/scripts/risk-tags.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/w"; mkdir -p "$W/app" "$W/alembic/versions"
  git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  echo 'x = 1' > "$W/app/q.py"; echo 'v = 1' > "$W/alembic/versions/001_a.py"
  git -C "$W" add -A; git -C "$W" commit -qm base
  B=$(git -C "$W" rev-parse HEAD)
  # Docs mentioning every risky word: ignored, clean.
  printf 'OAuth secret stripe DROP TABLE webhook\n' > "$W/README.md"; git -C "$W" add -A; git -C "$W" commit -qm docs
  set +e; "$S" --worktree "$W" --base "$B" --out "$TMP/d.json" >/dev/null 2>&1; rc=$?; set -e
  [ "$rc" -eq 0 ] || { echo "FAIL docs not ignored: exit $rc"; exit 1; }
  jq -e '.files_ignored==["README.md"] and .files_scanned==0' "$TMP/d.json" >/dev/null
  B1=$(git -C "$W" rev-parse HEAD)
  # A DELETE FROM in application code is not a destructive migration.
  echo 'Q = "DELETE FROM sessions_cache WHERE stale"' >> "$W/app/q.py"; git -C "$W" commit -qam app
  set +e; "$S" --worktree "$W" --base "$B1" --out "$TMP/a.json" >/dev/null 2>&1; rc=$?; set -e
  [ "$rc" -ne 3 ] || { echo "FAIL app-code DELETE escalated"; exit 1; }
  B2=$(git -C "$W" rev-parse HEAD)
  # The same statement inside an alembic revision escalates.
  echo 'op.execute("DELETE FROM sessions_cache")' >> "$W/alembic/versions/001_a.py"; git -C "$W" commit -qam mig
  set +e; "$S" --worktree "$W" --base "$B2" --out "$TMP/m.json" >/dev/null 2>&1; rc=$?; set -e
  [ "$rc" -eq 3 ] || { echo "FAIL migration DELETE not escalated: exit $rc"; exit 1; }
  echo PASS
expected: exit 0; stdout PASS. A README full of risky words is ignored (files_ignored lists it, exit 0); a DELETE FROM in app code does not escalate; the same statement in alembic/versions escalates (exit 3). MUTATION — removing ignore_paths from config/risk-tags.json, or the `_scope` check in scripts/risk-tags.sh, makes this fixture exit non-zero.
phase: bureau-lite · issue #100
owner: scripts/risk-tags.sh + config/risk-tags.json
