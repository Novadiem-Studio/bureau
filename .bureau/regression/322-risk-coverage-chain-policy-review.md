name: risk-coverage.sh proves every commit was scanned with the run's policy and every flagged record was reviewed
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  S="$ROOT/scripts/risk-tags.sh"; C="$ROOT/scripts/risk-coverage.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/w"; R="$TMP/run"; mkdir -p "$W" "$R/risk-tags"
  git -C "$W" init -q -b dev; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  echo 'x = 1' > "$W/a.py"; git -C "$W" add -A; git -C "$W" commit -qm base
  A=$(git -C "$W" rev-parse HEAD)
  printf '{"workflow":"bureau-lite","workflow_shifts":[],"git":{"base_sha":"%s","worktree_path":"%s"}}\n' "$A" "$W" > "$R/state.json"
  : > "$R/log.md"
  cov() { set +e; "$C" "$R" --out "$TMP/cov.json" >/dev/null 2>&1; rc=$?; set -e; }
  scan() { set +e; "$S" --worktree "$W" --base "$1" --policy-ref "$A" --out "$R/risk-tags/$2.json" >/dev/null 2>&1; set -e; }
  echo 'y = 2' >> "$W/a.py"; git -C "$W" commit -qam u1; scan "$A" 01
  U1=$(git -C "$W" rev-parse HEAD)
  echo 'API_KEY = env("K")' > "$W/keys.py"; git -C "$W" add -A; git -C "$W" commit -qm u2; scan "$U1" 02
  # 02 is flagged and unreviewed: not covered
  cov; [ "$rc" -eq 1 ] || { echo "FAIL unreviewed flag passed (rc $rc)"; exit 1; }
  sleep 1
  printf 'SPAWN-EVENT: {"role":"challenger","agent":"The Challenger","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"challenger-unit-02-1","status":"complete","at":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$R/log.md"
  cov; [ "$rc" -eq 0 ] || { echo "FAIL reviewed run not covered (rc $rc)"; cat "$TMP/cov.json"; exit 1; }
  jq -e '.coverage|startswith("REVIEW-COVERAGE: 2 records over 2 units; clean 1; reviewed 1")' "$TMP/cov.json" >/dev/null
  # an unscanned fix commit is a gap
  U2=$(git -C "$W" rev-parse HEAD)
  echo 'z = 3' >> "$W/a.py"; git -C "$W" commit -qam fix
  cov; [ "$rc" -eq 1 ] && jq -e 'any(.problems[]; startswith("gap:"))' "$TMP/cov.json" >/dev/null || { echo "FAIL gap not reported (rc $rc)"; exit 1; }
  scan "$U2" "02+1"; cov; [ "$rc" -eq 0 ] || { echo "FAIL follow-up did not close the gap (rc $rc)"; exit 1; }
  # a base-branch merge commit needs no record
  git -C "$W" checkout -q -b other "$A"; echo 'o = 1' > "$W/o.py"; git -C "$W" add -A; git -C "$W" commit -qm other
  git -C "$W" checkout -q dev; git -C "$W" merge -q --no-edit other
  cov; [ "$rc" -eq 0 ] || { echo "FAIL merge-only gap rejected (rc $rc)"; cat "$TMP/cov.json"; exit 1; }
  # a record scanned with a different policy ref is a problem
  M=$(git -C "$W" rev-parse HEAD)
  echo 'w = 4' >> "$W/a.py"; git -C "$W" commit -qam u3
  set +e; "$S" --worktree "$W" --base "$M" --out "$R/risk-tags/03.json" >/dev/null 2>&1; set -e
  cov; [ "$rc" -eq 1 ] && jq -e 'any(.problems[]; contains("project policy"))' "$TMP/cov.json" >/dev/null || { echo "FAIL policy mismatch not reported (rc $rc)"; exit 1; }
  # a run that never used bureau-lite is not applicable
  printf '{"workflow":"feature","workflow_shifts":[]}\n' > "$R/state.json"
  cov; [ "$rc" -eq 0 ] && jq -e '.result=="not_applicable"' "$TMP/cov.json" >/dev/null || { echo "FAIL not-applicable (rc $rc)"; exit 1; }
  echo PASS
expected: exit 0; stdout PASS. A flagged record with no later challenger-unit-02-N complete SPAWN-EVENT is not covered (exit 1); adding the review covers it and the coverage line counts 2 records, 1 clean, 1 reviewed; an unscanned fix commit is a reported gap until a 02+1 follow-up record closes it; a base-branch merge commit needs no record; a record whose policy_ref is not the run's base_sha is a problem; a feature run is not applicable (exit 0). MUTATION — removing the review-evidence check, the gap report, or the policy_ref comparison in scripts/risk-coverage.sh makes this fixture exit non-zero.
phase: bureau-lite · issue #100 (cold-review fixes)
owner: scripts/risk-coverage.sh
