name: risk-tags.sh routes clean / review / escalate by exit code and never copies the matched line
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  S="$ROOT/scripts/risk-tags.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/w"; mkdir -p "$W/app" "$W/migrations"
  git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  echo 'def page(): return "ok"' > "$W/app/views.py"
  echo 'select 1;' > "$W/migrations/001.sql"
  git -C "$W" add -A; git -C "$W" commit -qm base
  B0=$(git -C "$W" rev-parse HEAD)
  # 1. clean: a plain view change
  echo 'def page(): return "ok!"' > "$W/app/views.py"; git -C "$W" commit -qam c1
  set +e; "$S" --worktree "$W" --base "$B0" --out "$TMP/clean.json" >/dev/null 2>&1; rc=$?; set -e
  [ "$rc" -eq 0 ] || { echo "FAIL clean exit $rc"; exit 1; }
  jq -e '.result=="clean" and (.fired|length)==0' "$TMP/clean.json" >/dev/null
  B1=$(git -C "$W" rev-parse HEAD)
  # 2. review: a token store with a literal secret value
  printf 'import httpx\nREFRESH_TOKEN = "zz-literal-secret-zz"\n' > "$W/app/token_store.py"
  git -C "$W" add -A; git -C "$W" commit -qm c2
  set +e; "$S" --worktree "$W" --base "$B1" --out "$TMP/review.json" >/dev/null 2>&1; rc=$?; set -e
  [ "$rc" -eq 1 ] || { echo "FAIL review exit $rc"; exit 1; }
  jq -e '.result=="review" and (.review_tags|index("tokens-secrets")) and (.review_tags|index("network-egress")) and .escalate_tags==[]' "$TMP/review.json" >/dev/null
  jq -e '[.fired[].hits[] | select(.kind=="line")] | all(.line>0 and .side=="+")' "$TMP/review.json" >/dev/null
  if grep -q 'zz-literal-secret-zz' "$TMP/review.json"; then echo "FAIL: record copied the secret"; exit 1; fi
  B2=$(git -C "$W" rev-parse HEAD)
  # 3. escalate: a destructive migration
  echo 'ALTER TABLE users DROP COLUMN legacy;' >> "$W/migrations/001.sql"; git -C "$W" commit -qam c3
  set +e; "$S" --worktree "$W" --base "$B2" --out "$TMP/esc.json" >/dev/null 2>&1; rc=$?; set -e
  [ "$rc" -eq 3 ] || { echo "FAIL escalate exit $rc"; exit 1; }
  jq -e '.result=="escalate" and (.escalate_tags|index("destructive-migration"))' "$TMP/esc.json" >/dev/null
  # 4. error: unresolvable base fails closed with exit 2
  set +e; "$S" --worktree "$W" --base no-such-ref >/dev/null 2>&1; rc=$?; set -e
  [ "$rc" -eq 2 ] || { echo "FAIL error exit $rc"; exit 1; }
  echo PASS
expected: exit 0; stdout PASS. Exit codes 0/1/3/2 for clean, review (tokens-secrets + network-egress), escalate (destructive-migration) and an unresolvable ref; line hits carry line number and side; the record never contains the matched line's text. MUTATION — changing the escalate branch in scripts/risk-tags.sh (`if record["escalate_tags"]: finish("escalate")`) to finish("review"), or adding the line body to the hit entry, makes this fixture exit non-zero.
phase: bureau-lite · issue #100
owner: scripts/risk-tags.sh
