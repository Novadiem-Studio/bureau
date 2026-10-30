name: risk-tags.sh fails closed (exit 2 with a record) on a dirty tree, an empty or rewritten range, a bad config and a bad project regex
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  S="$ROOT/scripts/risk-tags.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/w"; mkdir -p "$W"
  git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  echo 'x = 1' > "$W/a.py"; git -C "$W" add -A; git -C "$W" commit -qm base
  A=$(git -C "$W" rev-parse HEAD)
  printf 'def require_csrf(r):\n    return check(r)\n' > "$W/guard.py"; git -C "$W" add -A; git -C "$W" commit -qm guard
  G=$(git -C "$W" rev-parse HEAD)
  expect2() {
    set +e; "$S" "$@" --out "$TMP/r.json" >/dev/null 2>&1; rc=$?; set -e
    [ "$rc" -eq 2 ] || { echo "FAIL ($1 $2 ...): exit $rc, want 2"; exit 1; }
    jq -e '.result=="error" and (.error|length>0)' "$TMP/r.json" >/dev/null || { echo "FAIL: no error record"; exit 1; }
  }
  # empty range
  expect2 --worktree "$W" --base "$G"
  # dirty tree: a staged, uncommitted key is never scanned as clean
  echo 'API_KEY = "x"' > "$W/k.py"; git -C "$W" add k.py
  expect2 --worktree "$W" --base "$A"
  git -C "$W" reset -q k.py; rm -f "$W/k.py"
  # rewritten history: reset past the guard commit, commit something else; old base is not an ancestor
  git -C "$W" reset -q --hard "$A"; echo 'y = 2' >> "$W/a.py"; git -C "$W" commit -qam other
  expect2 --worktree "$W" --base "$G"
  # bad config
  echo '{"tags": []}' > "$TMP/bad.json"
  expect2 --worktree "$W" --base "$A" --config "$TMP/bad.json"
  # a bad regex in a project tag's line_scope is an error record, not a traceback
  printf '```json risk_tags\n{"tags": [{"id": "x-new", "class": "review", "lines": ["foo"], "line_scope": "(unclosed"}]}\n```\n' > "$TMP/ctx.md"
  expect2 --worktree "$W" --base "$A" --project-context "$TMP/ctx.md"
  echo PASS
expected: exit 0; stdout PASS. Each of: empty range, staged-but-uncommitted change, a base orphaned by `reset --hard`, a config with no tags, and an uncompilable project line_scope exits 2 and writes a record with result "error". MUTATION — removing the dirty-tree check, the ancestry check, or the commit-count check in scripts/risk-tags.sh lets that case report clean (exit 0), and the fixture exits non-zero.
phase: bureau-lite · issue #100 (cold-review fixes)
owner: scripts/risk-tags.sh
