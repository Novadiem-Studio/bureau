name: risk-tags.sh always scans agent/skill/instruction files and nested docs code, and handles quoted paths
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  S="$ROOT/scripts/risk-tags.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/w"; mkdir -p "$W/.claude/agents" "$W/skills/x" "$W/src/docs" "$W/auth"
  git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  echo 'x = 1' > "$W/a.py"; git -C "$W" add -A; git -C "$W" commit -qm base
  run() {
    B=$(git -C "$W" rev-parse HEAD); eval "$2"; git -C "$W" add -A; git -C "$W" commit -qm "$1"
    set +e; "$S" --worktree "$W" --base "$B" --out "$TMP/$1.json" >/dev/null 2>&1; rc=$?; set -e
  }
  run agent "printf -- '---\nname: x\ntools: Bash, Write\n---\n' > '$W/.claude/agents/x.md'"
  [ "$rc" -eq 1 ] && jq -e '.review_tags|index("tool-allowlist")' "$TMP/agent.json" >/dev/null || { echo "FAIL agent .md (exit $rc)"; exit 1; }
  run skill "printf -- '---\nallowed-tools: Bash\n---\n' > '$W/skills/x/SKILL.md'"
  [ "$rc" -eq 1 ] && jq -e '.review_tags|index("tool-allowlist")' "$TMP/skill.json" >/dev/null || { echo "FAIL SKILL.md (exit $rc)"; exit 1; }
  for dir in workflows skills/x .codex .cursor; do
    mkdir -p "$W/$dir"
    run rules "printf -- '--allowed-tools Bash,Write\n' > '$W/$dir/rules.md'"
    [ "$rc" -eq 1 ] && jq -e '.review_tags|index("tool-allowlist")' "$TMP/rules.json" >/dev/null || { echo "FAIL $dir rules ignored (exit $rc)"; exit 1; }
  done
  mkdir -p "$W/.bureau/regression"
  run fixture "printf 'command: API_KEY=example ./probe\n' > '$W/.bureau/regression/01-probe.md'"
  [ "$rc" -eq 1 ] && jq -e '.review_tags|index("tokens-secrets")' "$TMP/fixture.json" >/dev/null || { echo "FAIL executable Markdown ignored (exit $rc)"; exit 1; }
  run nested "printf 'import httpx\nhttpx.post(URL)\n' > '$W/src/docs/handler.py'"
  [ "$rc" -eq 1 ] && jq -e '.review_tags|index("network-egress")' "$TMP/nested.json" >/dev/null || { echo "FAIL src/docs code (exit $rc)"; exit 1; }
  run quoted "printf 'x = 1\n' > '$W/auth/we\"ird.py'"
  [ "$rc" -eq 1 ] && jq -e 'any(.fired[]; .id=="oauth-auth" and any(.hits[]; .file=="auth/we\"ird.py"))' "$TMP/quoted.json" >/dev/null || { echo "FAIL quoted path (exit $rc)"; exit 1; }
  run readme "printf 'OAuth secret webhook\n' > '$W/README.md'"
  [ "$rc" -eq 0 ] || { echo "FAIL README not ignored (exit $rc)"; exit 1; }
  echo PASS
expected: exit 0; stdout PASS. `.claude/agents/x.md` with `tools:` and `skills/x/SKILL.md` with `allowed-tools:` trip tool-allowlist despite the .md ignore; code under src/docs/ is scanned (network-egress); a path git would quote (`auth/we"ird.py`) is matched under its real name; a README is still ignored. MUTATION — deleting ignore_except from config/risk-tags.json, or dropping -z from the name-status call in scripts/risk-tags.sh, makes this fixture exit non-zero.
phase: bureau-lite · issue #100 (cold-review fixes)
owner: scripts/risk-tags.sh + config/risk-tags.json
