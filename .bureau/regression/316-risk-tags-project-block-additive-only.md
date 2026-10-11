name: risk-tags.sh reads the project risk_tags block from the base commit, additively only
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  S="$ROOT/scripts/risk-tags.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/w"; mkdir -p "$W/app"
  git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  printf '# ctx\n\n```json risk_tags\n{"tags": [{"id": "upwork-api", "class": "review", "paths": ["(^|/)upwork/"], "lines": ["api\\\\.upwork\\\\.com"]}]}\n```\n' > "$W/project-context.md"
  echo 'x = 1' > "$W/app/a.py"
  git -C "$W" add -A; git -C "$W" commit -qm base
  B=$(git -C "$W" rev-parse HEAD)
  # A project tag from the base commit fires.
  echo 'URL = "https://api.upwork.com/graphql"' >> "$W/app/a.py"; git -C "$W" commit -qam c1
  set +e; "$S" --worktree "$W" --base "$B" --out "$TMP/a.json" >/dev/null 2>&1; rc=$?; set -e
  [ "$rc" -eq 1 ] || { echo "FAIL project tag exit $rc"; exit 1; }
  jq -e '(.review_tags|index("upwork-api")) and (.project_source|endswith(":project-context.md"))' "$TMP/a.json" >/dev/null
  B1=$(git -C "$W" rev-parse HEAD)
  # The run branch rewrites the block to ignore everything: not read (base wins), still fires.
  printf '```json risk_tags\n{"tags": [], "ignore_paths": [".*"]}\n```\n' > "$W/project-context.md"
  printf 'import httpx\nURL2 = "https://api.upwork.com/v2"\n' >> "$W/app/a.py"; git -C "$W" commit -qam c2
  set +e; "$S" --worktree "$W" --base "$B1" >/dev/null 2>&1; rc=$?; set -e
  [ "$rc" -eq 1 ] || { echo "FAIL run-branch block loosened the check: exit $rc"; exit 1; }
  # The same loosening block, once it IS the base (or passed explicitly), is refused: exit 2.
  set +e; "$S" --worktree "$W" --base "$B1" --project-context "$W/project-context.md" >/dev/null 2>&1; rc=$?; set -e
  [ "$rc" -eq 2 ] || { echo "FAIL ignore_paths block not refused: exit $rc"; exit 1; }
  printf '```json risk_tags\n{"tags": [{"id": "destructive-migration", "line_scope": ".*"}]}\n```\n' > "$TMP/narrow.md"
  set +e; "$S" --worktree "$W" --base "$B1" --project-context "$TMP/narrow.md" >/dev/null 2>&1; rc=$?; set -e
  [ "$rc" -eq 2 ] || { echo "FAIL line_scope on default tag not refused: exit $rc"; exit 1; }
  printf '```json risk_tags\n{"tags": [{"id": "network-egress", "class": "escalate"}]}\n```\n' > "$TMP/raise.md"
  set +e; "$S" --worktree "$W" --base "$B1" --project-context "$TMP/raise.md" >/dev/null 2>&1; rc=$?; set -e
  [ "$rc" -eq 3 ] || { echo "FAIL raise-to-escalate not honoured: exit $rc"; exit 1; }
  printf '```json risk_tags\n{"tags": [{"id": "money", "class": "review"}]}\n```\n' > "$TMP/lower.md"
  set +e; "$S" --worktree "$W" --base "$B1" --project-context "$TMP/lower.md" >/dev/null 2>&1; rc=$?; set -e
  [ "$rc" -eq 2 ] || { echo "FAIL lowering money not refused: exit $rc"; exit 1; }
  # An earlier unit empties the block (and trips risk-policy); a later unit's project tag
  # still fires because the policy is read from the run's start commit, not the unit base.
  B2=$(git -C "$W" rev-parse HEAD)
  printf '# ctx\n\n```json risk_tags\n{"tags": []}\n```\n' > "$W/project-context.md"; git -C "$W" commit -qam empty-block
  set +e; "$S" --worktree "$W" --base "$B2" --policy-ref "$B" --out "$TMP/p.json" >/dev/null 2>&1; rc=$?; set -e
  [ "$rc" -eq 1 ] && jq -e '.review_tags|index("risk-policy")' "$TMP/p.json" >/dev/null \
    || { echo "FAIL: emptying the block did not trip risk-policy (exit $rc)"; exit 1; }
  B3=$(git -C "$W" rev-parse HEAD)
  printf 'U = "https://api.upwork.com/v3"\n' >> "$W/app/a.py"; git -C "$W" commit -qam later
  set +e; "$S" --worktree "$W" --base "$B3" --policy-ref "$B" --out "$TMP/q.json" >/dev/null 2>&1; rc=$?; set -e
  [ "$rc" -eq 1 ] && jq -e --arg b "$B" '(.review_tags|index("upwork-api")) and .policy_ref==$b' "$TMP/q.json" >/dev/null \
    || { echo "FAIL: project tag lost after an earlier unit emptied the block (exit $rc)"; exit 1; }
  echo PASS
expected: exit 0; stdout PASS. A risk_tags block committed on --base adds a tag that fires; a block rewritten on the run branch is ignored because the default source is `git show <base>:project-context.md`; an explicit block that sets ignore_paths or a line_scope on a default tag exits 2; raising a default tag to escalate is honoured (exit 3) and lowering money is refused (exit 2); an earlier unit that empties the block trips risk-policy, and a later unit scanned with --policy-ref <start> still fires the project tag. MUTATION — reading project-context.md from the worktree instead of `git show <base>:`, deleting the ignore_paths refusal, or reading the block from --base instead of --policy-ref, makes this fixture exit non-zero.
phase: bureau-lite · issue #100
owner: scripts/risk-tags.sh
