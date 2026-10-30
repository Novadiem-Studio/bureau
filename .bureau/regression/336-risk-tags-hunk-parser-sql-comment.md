name: risk-tags.sh reads a removed SQL comment ("-- ..." shown as "--- ...") as a changed line, not a file header
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  S="$ROOT/scripts/risk-tags.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/w"; mkdir -p "$W/db"
  git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  printf 'select 1;\n-- legacy password column, see ticket\nselect 2;\n' > "$W/db/report.sql"
  git -C "$W" add -A; git -C "$W" commit -qm base
  B=$(git -C "$W" rev-parse HEAD)
  printf 'select 1;\nselect 2;\n' > "$W/db/report.sql"; git -C "$W" commit -qam c1
  set +e; "$S" --worktree "$W" --base "$B" --out "$TMP/r.json" >/dev/null 2>&1; rc=$?; set -e
  [ "$rc" -eq 1 ] || { echo "FAIL exit $rc"; exit 1; }
  jq -e 'any(.fired[]; .id=="tokens-secrets" and any(.hits[]; .kind=="line" and .side=="-" and .line==2 and .file=="db/report.sql"))' "$TMP/r.json" >/dev/null \
    || { echo "FAIL: removed comment line not attributed"; cat "$TMP/r.json"; exit 1; }
  echo PASS
expected: exit 0; stdout PASS. The removed line "-- legacy password column" appears in the -U0 diff as "--- legacy password column"; the hunk-counter parser reads it as removed line 2 of db/report.sql and tokens-secrets fires on it. MUTATION — dropping the hunk counters in scripts/risk-tags.sh (so any line starting "--- " is taken as a header) loses the hit and the fixture exits non-zero.
phase: bureau-lite · issue #100
owner: scripts/risk-tags.sh
