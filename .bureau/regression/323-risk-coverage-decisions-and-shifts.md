name: risk-coverage.sh requires Robin's logged decision on escalates, catches a log/state shift mismatch, ends at an upshift, and gates preflight final
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  S="$ROOT/scripts/risk-tags.sh"; C="$ROOT/scripts/risk-coverage.sh"; L="$ROOT/scripts/log-append.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/w"; R="$TMP/run"; mkdir -p "$W" "$R/risk-tags"
  git -C "$W" init -q -b main; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  echo 'x = 1' > "$W/a.py"; git -C "$W" add -A; git -C "$W" commit -qm base
  A=$(git -C "$W" rev-parse HEAD); git -C "$W" checkout -q -b run
  st() { printf '{"workflow":"%s","workflow_shifts":%s,"target_repo":"(no-target)","git":{"base_sha":"%s","base_branch":"main","worktree_path":"%s"}}\n' "$1" "$2" "$A" "$W" > "$R/state.json"; }
  st bureau-lite '[]'; : > "$R/log.md"
  printf '**FR 1 — x**\nA requirement.\n' > "$R/spec.md"; printf '## Phase 1: x\nThis implements FR 1.\n' > "$R/plan.md"
  cov() { set +e; "$C" "$R" --out "$TMP/cov.json" >/dev/null 2>&1; rc=$?; set -e; }
  echo 'charge = stripe.Charge.create(amount=1)' > "$W/pay.py"; git -C "$W" add -A; git -C "$W" commit -qm u1
  set +e; "$S" --worktree "$W" --base "$A" --policy-ref "$A" --out "$R/risk-tags/01.json" >/dev/null 2>&1; rc=$?; set -e
  [ "$rc" -eq 3 ] || { echo "FAIL money did not escalate (rc $rc)"; exit 1; }
  sleep 1
  for st in started complete; do
    printf 'SPAWN-EVENT: {"role":"challenger","agent":"The Challenger","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"challenger-unit-01-1","status":"%s","at":"%s"}\n' "$st" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$R/log.md"
  done
  # reviewed but no decision: not covered, and preflight final flags it
  cov; [ "$rc" -eq 1 ] && jq -e 'any(.problems[]; contains("Robin"))' "$TMP/cov.json" >/dev/null || { echo "FAIL escalate without decision covered (rc $rc)"; exit 1; }
  set +e; out=$("$ROOT/scripts/preflight-artifacts.sh" "$R" --phase final 2>&1); prc=$?; set -e
  [ "$prc" -eq 1 ] && printf '%s' "$out" | grep -q 'risk-coverage' || { echo "FAIL preflight final missed coverage (rc $prc): $out"; exit 1; }
  "$L" "$R" 'RISK-TAGS waiver: unit 01 money; by Robin: "test charge only"' >/dev/null
  cov; [ "$rc" -eq 0 ] || { echo "FAIL waiver heading not honoured (rc $rc)"; cat "$TMP/cov.json"; exit 1; }
  set +e; "$ROOT/scripts/preflight-artifacts.sh" "$R" --phase final >/dev/null 2>&1; prc=$?; set -e
  [ "$prc" -eq 0 ] || { echo "FAIL preflight final still flags a covered run (rc $prc)"; exit 1; }
  # upshift: units after the shift's head need no records
  H=$(git -C "$W" rev-parse HEAD)
  echo 'w = 2' >> "$W/a.py"; git -C "$W" commit -qam heavy-unit
  cov; [ "$rc" -eq 1 ] || { echo "FAIL unscanned unit passed before the upshift was recorded"; exit 1; }
  st bureau-lite "[{\"from\":\"bureau-lite\",\"to\":\"execute-plan\",\"effective_from\":\"02\",\"head\":\"$H\",\"by\":\"conductor\"}]"
  cov; [ "$rc" -eq 0 ] || { echo "FAIL chain did not end at the upshift head (rc $rc)"; cat "$TMP/cov.json"; exit 1; }
  st bureau-lite '[{"from":"bureau-lite","to":"execute-plan","effective_from":"02","by":"conductor"}]'
  cov; [ "$rc" -eq 2 ] || { echo "FAIL upshift without head accepted (rc $rc)"; exit 1; }
  # a logged shift to bureau-lite that state.json lacks is an error, not "not applicable"
  st execute-plan '[]'
  "$L" "$R" 'WORKFLOW-SHIFT: execute-plan to bureau-lite from unit 05' >/dev/null
  cov; [ "$rc" -eq 2 ] || { echo "FAIL log/state shift mismatch passed (rc $rc)"; exit 1; }
  echo PASS
expected: exit 0; stdout PASS. A money escalate with a Challenger review but no decision is not covered and preflight-artifacts --phase final reports a risk-coverage defect; a later `RISK-TAGS waiver` heading (via log-append.sh) covers it and preflight passes; an unscanned unit after the lite run fails until an upshift entry with `head` ends the chain there; an upshift without `head` is exit 2; a WORKFLOW-SHIFT heading to bureau-lite with no state.json entry is exit 2. MUTATION — dropping the escalate decision check, the log/state shift check, or the upshift end in scripts/risk-coverage.sh, or the coverage block in scripts/preflight-artifacts.sh, makes this fixture exit non-zero.
phase: bureau-lite · issue #100 (cold-review fixes)
owner: scripts/risk-coverage.sh + scripts/preflight-artifacts.sh
