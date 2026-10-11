name: risk-coverage.sh proves every commit was scanned, re-scans every record, and requires a challenger-role review after each flag
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  S="$ROOT/scripts/risk-tags.sh"; C="$ROOT/scripts/risk-coverage.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/w"; R="$TMP/run"; mkdir -p "$W" "$R/risk-tags"
  git -C "$W" init -q -b main; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  echo 'x = 1' > "$W/a.py"; git -C "$W" add -A; git -C "$W" commit -qm base
  A=$(git -C "$W" rev-parse HEAD); git -C "$W" checkout -q -b run
  printf '{"workflow":"bureau-lite","workflow_shifts":[],"git":{"base_sha":"%s","base_branch":"main","worktree_path":"%s"}}\n' "$A" "$W" > "$R/state.json"
  : > "$R/log.md"
  cov() { set +e; "$C" "$R" --out "$TMP/cov.json" >/dev/null 2>&1; rc=$?; set -e; }
  scan() { set +e; "$S" --worktree "$W" --base "$1" --policy-ref "$A" --out "$R/risk-tags/$2.json" >/dev/null 2>&1; set -e; }
  ev() { printf 'SPAWN-EVENT: {"role":"%s","agent":"x","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"%s","status":"complete","at":"%s"}\n' "$1" "$2" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$R/log.md"; }
  echo 'y = 2' >> "$W/a.py"; git -C "$W" commit -qam u1; scan "$A" 01
  U1=$(git -C "$W" rev-parse HEAD)
  echo 'API_KEY = env("K")' > "$W/keys.py"; git -C "$W" add -A; git -C "$W" commit -qm u2; scan "$U1" 02
  cov; [ "$rc" -eq 1 ] || { echo "FAIL unreviewed flag passed (rc $rc)"; exit 1; }
  sleep 1
  # a non-challenger role with the right attempt id does not count
  ev mage challenger-unit-02-1
  cov; [ "$rc" -eq 1 ] || { echo "FAIL mage event counted as a review (rc $rc)"; exit 1; }
  ev challenger challenger-unit-02-1
  cov; [ "$rc" -eq 0 ] || { echo "FAIL reviewed run not covered (rc $rc)"; cat "$TMP/cov.json"; exit 1; }
  jq -e '.coverage|startswith("REVIEW-COVERAGE: 2 records over 2 units; clean 1; reviewed 1")' "$TMP/cov.json" >/dev/null
  # a record edited from review to clean is caught by the re-scan
  cp "$R/risk-tags/02.json" "$TMP/02.bak"
  jq '.result="clean" | .review_tags=[]' "$TMP/02.bak" > "$R/risk-tags/02.json"
  cov; [ "$rc" -eq 1 ] && jq -e 'any(.problems[]; contains("re-scan"))' "$TMP/cov.json" >/dev/null || { echo "FAIL tampered record not caught (rc $rc)"; exit 1; }
  cp "$TMP/02.bak" "$R/risk-tags/02.json"
  # an unscanned fix commit is a gap until a follow-up record closes it
  U2=$(git -C "$W" rev-parse HEAD)
  echo 'z = 3' >> "$W/a.py"; git -C "$W" commit -qam fix
  cov; [ "$rc" -eq 1 ] && jq -e 'any(.problems[]; startswith("gap:"))' "$TMP/cov.json" >/dev/null || { echo "FAIL gap not reported (rc $rc)"; exit 1; }
  scan "$U2" "02+1"; cov; [ "$rc" -eq 0 ] || { echo "FAIL follow-up did not close the gap (rc $rc)"; exit 1; }
  # merging the base branch needs no record
  git -C "$W" checkout -q main; echo 'm = 1' > "$W/m.py"; git -C "$W" add -A; git -C "$W" commit -qm main-moves
  git -C "$W" checkout -q run; git -C "$W" merge -q --no-ff --no-edit main
  cov; [ "$rc" -eq 0 ] || { echo "FAIL base-branch merge rejected (rc $rc)"; cat "$TMP/cov.json"; exit 1; }
  # merging a side branch is a gap: it can carry code no record scanned
  git -C "$W" checkout -q -b side "$A"; echo 'TOKEN = "sk-live"' > "$W/t.py"; git -C "$W" add -A; git -C "$W" commit -qm side
  git -C "$W" checkout -q run; git -C "$W" merge -q --no-ff --no-edit side
  cov; [ "$rc" -eq 1 ] && jq -e 'any(.problems[]; contains("not on the base branch"))' "$TMP/cov.json" >/dev/null || { echo "FAIL side merge accepted (rc $rc)"; exit 1; }
  # a feature run is not applicable
  printf '{"workflow":"feature","workflow_shifts":[]}\n' > "$R/state.json"; : > "$R/log.md"
  cov; [ "$rc" -eq 0 ] && jq -e '.result=="not_applicable"' "$TMP/cov.json" >/dev/null || { echo "FAIL not-applicable (rc $rc)"; exit 1; }
  echo PASS
expected: exit 0; stdout PASS. A flagged record is not covered until a complete challenger-role SPAWN-EVENT challenger-unit-02-1 follows it (a mage event with that id does not count); a record edited from review to clean is caught by the re-scan; an unscanned fix commit is a gap until a 02+1 record closes it; a merge of the base branch needs no record but a merge of a side branch is a gap; a feature run is not applicable. MUTATION — removing the role check, the re-scan comparison, the gap report, or the base-branch ancestry test for merges in scripts/risk-coverage.sh makes this fixture exit non-zero.
phase: bureau-lite · issue #100 (cold-review fixes)
owner: scripts/risk-coverage.sh
