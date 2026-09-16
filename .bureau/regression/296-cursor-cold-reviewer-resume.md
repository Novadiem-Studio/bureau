name: Cursor cold reviewer is two-phase — plan exits 2 with a Task plan, --resume binds the Task response to that plan, validates the verdict against the schema, and writes verdict + envelope atomically
phase: multi-host Cursor adapter (issue #54)
owner: scripts/run-cold-reviewer.sh cursor branch; docs/host-cursor.md § Cold reviewer
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  trap 'rm -rf "$TMPF"' EXIT INT TERM
  RD="$TMPF/run"
  CTX="$RD/checkpoints/01-context"
  CP="$RD/checkpoints"
  mkdir -p "$CTX/conventions"
  printf '# reviewer\n' > "$CTX/delegate-reviewer.md"
  cp "$ROOT/AGENTS.md" "$CTX/bureau-agents.md"
  printf '# conventions\n' > "$CTX/conventions.md"
  printf '# module\n' > "$CTX/conventions/agent-contracts.md"
  printf '# slice\n' > "$CTX/log-slice.md"
  printf '# artifact\n' > "$CTX/artifact.md"
  HASH=$(shasum -a 256 "$CTX/artifact.md" | awk '{print $1}')
  printf '{"target_repo":"%s","scope":{}}\n' "$TMPF/target" > "$CTX/state.json"
  cp "$CTX/state.json" "$RD/state.json"
  : > "$RD/log.md"
  cat > "$RD/model-routing.json" <<JSON
  {"runtime":"cursor","roles":{"delegate":{"model":"gpt-5.6-sol-medium"}},"hostPolicy":{"allowed_spawn_models":["composer-2.5-fast","gpt-5.6-sol-medium","cursor-grok-4.6-high-fast","claude-opus-5-thinking-high"]}}
  JSON
  run() { bash "$ROOT/scripts/run-cold-reviewer.sh" "$@"; }

  # ── phase 1: plan ──────────────────────────────────────────────────────────
  set +e
  plan_out=$(run "$RD" "$CTX" 01 01-1-1 artifact.md routine 2>"$TMPF/plan-err")
  rc=$?
  set -e
  [ "$rc" -eq 2 ] || { echo "FAIL: plan phase rc $rc, expected 2"; cat "$TMPF/plan-err"; exit 1; }
  grep -q 'CURSOR-REVIEWER-HOST-TASK-REQUIRED' "$TMPF/plan-err" || { echo "FAIL: no host-task line"; exit 1; }
  PLAN="$CP/01-1-1-reviewer-task-plan.json"
  [ -f "$PLAN" ] || { echo "FAIL: plan file missing"; exit 1; }
  printf '%s' "$plan_out" | jq -e '.status == "host-task-required"' >/dev/null || { echo "FAIL: plan not on stdout"; exit 1; }
  jq -e --arg h "$HASH" --arg ctx "$(cd "$CTX" && pwd -P)" '
    .transport == "cursor-task" and .status == "host-task-required" and .model == "gpt-5.6-sol-medium"
    and .artifactSha256 == $h and .ctx == $ctx and .spawnId == "01-1-1" and .checkpoint == "01"
    and (.taskPrompt | test("artifact.sha256")) and (.responsePath | endswith("01-1-1-reviewer-task-response.json"))
  ' "$PLAN" >/dev/null || { echo "FAIL: plan payload drifted"; cat "$PLAN"; exit 1; }
  [ ! -e "$CP/01-1-1-reviewer-verdict.json" ] || { echo "FAIL: plan phase wrote a verdict"; exit 1; }
  [ -f "$CTX/artifact.sha256" ] || { echo "FAIL: artifact.sha256 not staged"; exit 1; }

  # ── refusals: nothing durable is written ───────────────────────────────────
  refuse() {  # <label> <response-json>
    printf '%s\n' "$2" > "$TMPF/resp.json"
    set +e
    run --resume "$TMPF/resp.json" "$RD" "$CTX" 01 01-1-1 artifact.md routine >"$TMPF/out" 2>"$TMPF/err"
    r=$?
    set -e
    [ "$r" -eq 1 ] || { echo "FAIL: $1 rc $r, expected 1"; cat "$TMPF/err"; exit 1; }
    [ ! -e "$CP/01-1-1-reviewer-verdict.json" ] || { echo "FAIL: $1 left a verdict file"; exit 1; }
    [ ! -e "$CP/01-1-1-reviewer-envelope.json" ] || { echo "FAIL: $1 left an envelope"; exit 1; }
    [ "$(jq -r .status "$PLAN")" = "host-task-required" ] || { echo "FAIL: $1 consumed the plan"; exit 1; }
    if ls "$CP"/.01-1-1-* >/dev/null 2>&1; then echo "FAIL: $1 left temp files"; exit 1; fi
    [ ! -e "$CP/01-1-1-reviewer-cursor-raw.json" ] || { echo "FAIL: $1 persisted the rejected raw response"; exit 1; }
    [ ! -e "$CP/01-1-1-reviewer-task-plan.claim" ] || { echo "FAIL: $1 left a claim behind"; exit 1; }
    return 0
  }
  refuse "missing-field" "{\"Decision\":\"proceed\",\"Artifact-hash\":\"$HASH\",\"Uncertainties\":\"none\",\"Rationale\":\"r\",\"Required-changes\":\"none\",\"Escalation\":\"none\"}"
  refuse "extra-key" "{\"Decision\":\"proceed\",\"Artifact-hash\":\"$HASH\",\"Uncertainties\":\"none\",\"Rationale\":\"r\",\"Required-changes\":\"none\",\"Escalation\":\"none\",\"Ledger\":\"l\",\"Bonus\":1}"
  refuse "bad-decision" "{\"Decision\":\"maybe\",\"Artifact-hash\":\"$HASH\",\"Uncertainties\":\"none\",\"Rationale\":\"r\",\"Required-changes\":\"none\",\"Escalation\":\"none\",\"Ledger\":\"l\"}"
  refuse "bad-hash-shape" "{\"Decision\":\"proceed\",\"Artifact-hash\":\"nothex\",\"Uncertainties\":\"none\",\"Rationale\":\"r\",\"Required-changes\":\"none\",\"Escalation\":\"none\",\"Ledger\":\"l\"}"
  refuse "not-json" "this is not json"
  grep -q 'rejected against' "$TMPF/err" || grep -q 'not JSON' "$TMPF/err" || { echo "FAIL: refusal reason not stated"; cat "$TMPF/err"; exit 1; }
  # no plan for this spawn id
  printf '{"Decision":"proceed"}\n' > "$TMPF/resp.json"
  set +e
  run --resume "$TMPF/resp.json" "$RD" "$CTX" 01 01-9-9 artifact.md routine >/dev/null 2>"$TMPF/err"; r=$?
  set -e
  [ "$r" -eq 1 ] && grep -q 'no Cursor reviewer Task plan' "$TMPF/err" || { echo "FAIL: resume without plan not refused"; cat "$TMPF/err"; exit 1; }
  # staged artifact changed after the plan → digest mismatch with the plan
  printf '# artifact v2\n' > "$CTX/artifact.md"
  set +e
  run --resume "$TMPF/resp.json" "$RD" "$CTX" 01 01-1-1 artifact.md routine >/dev/null 2>"$TMPF/err"; r=$?
  set -e
  [ "$r" -eq 1 ] && grep -q 'artifactSha256 mismatch' "$TMPF/err" || { echo "FAIL: changed artifact not refused"; cat "$TMPF/err"; exit 1; }
  printf '# artifact\n' > "$CTX/artifact.md"
  # --resume on a non-cursor host
  printf '{"runtime":"claude","roles":{"delegate":{"model":"opus"}}}\n' > "$TMPF/claude-routing.json"
  set +e
  # via env, not `VAR=x func`: in POSIX sh an assignment before a function call persists afterwards
  env BUREAU_REVIEWER_HOST=claude bash "$ROOT/scripts/run-cold-reviewer.sh" --resume "$TMPF/resp.json" "$RD" "$CTX" 01 01-1-1 artifact.md routine >/dev/null 2>"$TMPF/err"; r=$?
  set -e
  [ "$r" -eq 1 ] && grep -q 'applies only to the cursor host' "$TMPF/err" || { echo "FAIL: --resume on claude not refused"; cat "$TMPF/err"; exit 1; }

  # ── phase 2: resume with a good response wrapped in .result + usage ────────
  cat > "$TMPF/resp.json" <<JSON
  {"result":{"Decision":"revise","Artifact-hash":"$HASH","Uncertainties":"none","Rationale":"fixture","Required-changes":"architecture: tighten the lease","Escalation":"none","Ledger":"fixture","Integration-evidence":null},"usage":{"input_tokens":100,"cached_input_tokens":40,"cache_write_input_tokens":5,"output_tokens":20},"num_turns":3}
  JSON
  META=$(run --resume "$TMPF/resp.json" "$RD" "$CTX" 01 01-1-1 artifact.md routine 2>"$TMPF/err")
  rc=$?
  [ "$rc" -eq 0 ] || { echo "FAIL: resume rc $rc"; cat "$TMPF/err"; exit 1; }
  printf '%s' "$META" | jq -e --arg h "$HASH" '
    .runtime == "cursor" and .model == "gpt-5.6-sol-medium" and .hash_match == true and .artifact_sha256 == $h
    and (.plan_path | endswith("01-1-1-reviewer-task-plan.json"))
  ' >/dev/null || { echo "FAIL: meta drifted"; printf '%s\n' "$META"; exit 1; }
  VP=$(printf '%s' "$META" | jq -r .verdict_path); EP=$(printf '%s' "$META" | jq -r .envelope_path)
  jq -e --arg h "$HASH" '.Decision == "revise" and ."Artifact-hash" == $h and (has("Integration-evidence") | not)' "$VP" >/dev/null \
    || { echo "FAIL: normalized verdict"; cat "$VP"; exit 1; }
  jq -e '
    .type == "bureau-cold-review-result" and .runtime == "cursor" and .result.Decision == "revise" and .num_turns == 3
    and .usage.input_tokens == 100 and .usage.cache_read_input_tokens == 40 and .usage.cache_creation_input_tokens == 5 and .usage.output_tokens == 20
  ' "$EP" >/dev/null || { echo "FAIL: envelope"; cat "$EP"; exit 1; }
  [ -f "$CP/01-1-1-reviewer-events.jsonl" ] && [ -f "$CP/01-1-1-reviewer-cursor-raw.json" ] || { echo "FAIL: events/raw files"; exit 1; }
  jq -e '.status == "resumed" and (.resumedAt | length > 0) and (.responseSha256 | test("^[a-f0-9]{64}$"))' "$PLAN" >/dev/null \
    || { echo "FAIL: plan not marked resumed"; cat "$PLAN"; exit 1; }
  grep -q 'Cold reviewer resume — spawn: 01-1-1' "$RD/log.md" || { echo "FAIL: resume audit line missing"; exit 1; }
  if ls "$CP"/.01-1-1-* >/dev/null 2>&1; then echo "FAIL: temp files left after resume"; exit 1; fi
  # append-reviewer-tokens.sh accepts the envelope as-is (one event, no crash)
  bash "$ROOT/scripts/append-reviewer-tokens.sh" "$RD" 01 01-1-1 "$(jq -c . "$EP")" >/dev/null 2>&1 \
    || { echo "FAIL: envelope rejected by append-reviewer-tokens.sh"; exit 1; }

  [ ! -e "$CP/01-1-1-reviewer-task-plan.claim" ] || { echo "FAIL: claim not released after success"; exit 1; }

  # double resume of the same spawn is refused; each spawn is counted once
  set +e
  run --resume "$TMPF/resp.json" "$RD" "$CTX" 01 01-1-1 artifact.md routine >/dev/null 2>"$TMPF/err"; r=$?
  set -e
  [ "$r" -eq 1 ] && grep -q "already 'resumed'" "$TMPF/err" || { echo "FAIL: double resume not refused"; cat "$TMPF/err"; exit 1; }
  # re-planning a resumed spawn is refused and does not touch its outputs
  VSHA_BEFORE=$(shasum -a 256 "$VP" | awk '{print $1}')
  set +e
  run "$RD" "$CTX" 01 01-1-1 artifact.md routine >/dev/null 2>"$TMPF/err"; r=$?
  set -e
  [ "$r" -eq 1 ] && grep -q 'already exists for spawn 01-1-1' "$TMPF/err" || { echo "FAIL: re-plan of a resumed spawn not refused"; cat "$TMPF/err"; exit 1; }
  [ "$(shasum -a 256 "$VP" | awk '{print $1}')" = "$VSHA_BEFORE" ] || { echo "FAIL: re-plan replaced the published verdict"; exit 1; }
  [ "$(jq -r .status "$PLAN")" = "resumed" ] || { echo "FAIL: re-plan replaced the plan"; exit 1; }

  # concurrent resumes of one plan: exactly one publishes
  set +e
  run "$RD" "$CTX" 01 01-1-3 artifact.md routine >/dev/null 2>&1
  set -e
  set +e
  run --resume "$TMPF/resp.json" "$RD" "$CTX" 01 01-1-3 artifact.md routine >"$TMPF/c1.out" 2>"$TMPF/c1.err" & P1=$!
  run --resume "$TMPF/resp.json" "$RD" "$CTX" 01 01-1-3 artifact.md routine >"$TMPF/c2.out" 2>"$TMPF/c2.err" & P2=$!
  wait "$P1"; R1=$?
  wait "$P2"; R2=$?
  set -e
  # at least one succeeds; the other either lost the claim (rc 1) or arrived after the raw was published and completed as a benign replay (rc 0)
  [ $((R1 + R2)) -le 1 ] || { echo "FAIL: concurrent resumes: rc $R1 and $R2 (expected at least one success)"; cat "$TMPF/c1.err" "$TMPF/c2.err"; exit 1; }
  [ "$(ls "$CP"/01-1-3-reviewer-verdict.json 2>/dev/null | wc -l | tr -d ' ')" = "1" ] || { echo "FAIL: concurrent resumes did not publish exactly one verdict"; exit 1; }
  [ "$(jq -r .status "$CP/01-1-3-reviewer-task-plan.json")" = "resumed" ] || { echo "FAIL: concurrent winner did not mark the plan"; exit 1; }
  [ ! -e "$CP/01-1-3-reviewer-task-plan.claim" ] || { echo "FAIL: concurrent loser left a claim"; exit 1; }

  # a stale claim (a resume that died before publishing) is refused with a recovery hint; removing it retries
  set +e
  run "$RD" "$CTX" 01 01-1-4 artifact.md routine >/dev/null 2>&1
  set -e
  mkdir "$CP/01-1-4-reviewer-task-plan.claim"
  printf '{"pid":"0","at":"2026-09-15T00:00:00Z"}\n' > "$CP/01-1-4-reviewer-task-plan.claim/claim.json"
  set +e
  run --resume "$TMPF/resp.json" "$RD" "$CTX" 01 01-1-4 artifact.md routine >/dev/null 2>"$TMPF/err"; r=$?
  set -e
  [ "$r" -eq 1 ] && grep -q 'already claimed' "$TMPF/err" && grep -q 'remove' "$TMPF/err" || { echo "FAIL: stale claim not refused with a recovery hint"; cat "$TMPF/err"; exit 1; }
  [ ! -e "$CP/01-1-4-reviewer-verdict.json" ] || { echo "FAIL: stale claim case published"; exit 1; }
  rm -rf "$CP/01-1-4-reviewer-task-plan.claim"
  run --resume "$TMPF/resp.json" "$RD" "$CTX" 01 01-1-4 artifact.md routine >/dev/null 2>"$TMPF/err" || { echo "FAIL: resume after clearing the stale claim failed"; cat "$TMPF/err"; exit 1; }

  # an interrupted resume (published, never marked) completes on replay with the SAME response only
  set +e
  run "$RD" "$CTX" 01 01-1-5 artifact.md routine >/dev/null 2>&1
  set -e
  run --resume "$TMPF/resp.json" "$RD" "$CTX" 01 01-1-5 artifact.md routine >/dev/null 2>&1 || { echo "FAIL: 01-1-5 resume"; exit 1; }
  P5="$CP/01-1-5-reviewer-task-plan.json"
  jq '.status = "host-task-required" | del(.resumedAt, .responseFile, .responseSha256)' "$P5" > "$TMPF/p5" && mv "$TMPF/p5" "$P5"
  V5SHA=$(shasum -a 256 "$CP/01-1-5-reviewer-verdict.json" | awk '{print $1}')
  printf '{"Decision":"proceed","Artifact-hash":"%s","Uncertainties":"none","Rationale":"other","Required-changes":"none","Escalation":"none","Ledger":"l"}\n' "$HASH" > "$TMPF/other.json"
  set +e
  run --resume "$TMPF/other.json" "$RD" "$CTX" 01 01-1-5 artifact.md routine >/dev/null 2>"$TMPF/err"; r=$?
  set -e
  [ "$r" -eq 1 ] && grep -q 'from a different response' "$TMPF/err" || { echo "FAIL: replay with a different response not refused"; cat "$TMPF/err"; exit 1; }
  META5=$(run --resume "$TMPF/resp.json" "$RD" "$CTX" 01 01-1-5 artifact.md routine 2>"$TMPF/err") || { echo "FAIL: replay with the same response failed"; cat "$TMPF/err"; exit 1; }
  [ "$(jq -r .status "$P5")" = "resumed" ] || { echo "FAIL: replay did not mark the plan"; exit 1; }
  [ "$(shasum -a 256 "$CP/01-1-5-reviewer-verdict.json" | awk '{print $1}')" = "$V5SHA" ] || { echo "FAIL: replay replaced the published verdict"; exit 1; }
  grep -q 'Cold reviewer resume replay — spawn: 01-1-5' "$RD/log.md" || { echo "FAIL: replay line missing"; exit 1; }
  [ "$(grep -c 'Cold reviewer resume — spawn: 01-1-5,' "$RD/log.md")" = "1" ] || { echo "FAIL: audit line of record written more than once"; exit 1; }

  # partial publication: raw goes first, so a crash after any link is completed by replay
  set +e
  run "$RD" "$CTX" 01 01-1-6 artifact.md routine >/dev/null 2>&1
  set -e
  run --resume "$TMPF/resp.json" "$RD" "$CTX" 01 01-1-6 artifact.md routine >/dev/null 2>&1 || { echo "FAIL: 01-1-6 resume"; exit 1; }
  P6="$CP/01-1-6-reviewer-task-plan.json"
  V6SHA=$(shasum -a 256 "$CP/01-1-6-reviewer-verdict.json" | awk '{print $1}')
  reset6() { jq '.status = "host-task-required" | del(.resumedAt, .responseFile, .responseSha256)' "$P6" > "$TMPF/p6" && mv "$TMPF/p6" "$P6"; }
  # crashed right after the raw link: verdict and envelope missing
  reset6; rm -f "$CP/01-1-6-reviewer-verdict.json" "$CP/01-1-6-reviewer-envelope.json"
  META6=$(run --resume "$TMPF/resp.json" "$RD" "$CTX" 01 01-1-6 artifact.md routine 2>"$TMPF/err") || { echo "FAIL: replay after raw-only crash"; cat "$TMPF/err"; exit 1; }
  [ -f "$CP/01-1-6-reviewer-verdict.json" ] && [ -f "$CP/01-1-6-reviewer-envelope.json" ] || { echo "FAIL: replay did not republish the missing outputs"; exit 1; }
  [ "$(shasum -a 256 "$CP/01-1-6-reviewer-verdict.json" | awk '{print $1}')" = "$V6SHA" ] || { echo "FAIL: replayed verdict differs from the original"; exit 1; }
  printf '%s' "$META6" | jq -e '.hash_match == true' >/dev/null || { echo "FAIL: replay meta"; exit 1; }
  # crashed right after the verdict link: envelope missing
  reset6; rm -f "$CP/01-1-6-reviewer-envelope.json"
  run --resume "$TMPF/resp.json" "$RD" "$CTX" 01 01-1-6 artifact.md routine >/dev/null 2>"$TMPF/err" || { echo "FAIL: replay after verdict-only crash"; cat "$TMPF/err"; exit 1; }
  [ -f "$CP/01-1-6-reviewer-envelope.json" ] || { echo "FAIL: envelope not republished"; exit 1; }
  [ "$(jq -r .status "$P6")" = "resumed" ] || { echo "FAIL: replay did not mark the plan"; exit 1; }
  [ "$(grep -c 'Cold reviewer resume — spawn: 01-1-6,' "$RD/log.md")" = "1" ] || { echo "FAIL: 01-1-6 audit line not idempotent"; exit 1; }
  [ ! -e "$CP/01-1-6-reviewer-task-plan.claim" ] || { echo "FAIL: claim left after replay"; exit 1; }
  # a published output that no longer matches what the response derives is never replaced
  reset6
  printf '{"tampered":true}\n' > "$CP/01-1-6-reviewer-verdict.json"
  set +e
  run --resume "$TMPF/resp.json" "$RD" "$CTX" 01 01-1-6 artifact.md routine >/dev/null 2>"$TMPF/err"; r=$?
  set -e
  [ "$r" -eq 1 ] && grep -q 'differs from what this response derives' "$TMPF/err" || { echo "FAIL: tampered output not refused"; cat "$TMPF/err"; exit 1; }
  grep -q tampered "$CP/01-1-6-reviewer-verdict.json" || { echo "FAIL: tampered output was replaced"; exit 1; }
  [ "$(jq -r .status "$P6")" = "host-task-required" ] || { echo "FAIL: refused replay marked the plan"; exit 1; }
  # output with no raw response behind it cannot be bound: refused
  set +e
  run "$RD" "$CTX" 01 01-1-7 artifact.md routine >/dev/null 2>&1
  set -e
  printf '{"orphan":true}\n' > "$CP/01-1-7-reviewer-verdict.json"
  set +e
  run --resume "$TMPF/resp.json" "$RD" "$CTX" 01 01-1-7 artifact.md routine >/dev/null 2>"$TMPF/err"; r=$?
  set -e
  [ "$r" -eq 1 ] && grep -q 'no raw response to bind it to' "$TMPF/err" || { echo "FAIL: orphan output not refused"; cat "$TMPF/err"; exit 1; }
  [ ! -e "$CP/01-1-7-reviewer-task-plan.claim" ] || { echo "FAIL: orphan refusal left a claim"; exit 1; }

  # a bare verdict with no usage: envelope carries a _note, no fabricated zeros; hash mismatch is reported, not refused
  set +e
  run "$RD" "$CTX" 01 01-1-2 artifact.md routine >/dev/null 2>&1
  set -e
  printf '{"Decision":"proceed","Artifact-hash":"%s","Uncertainties":"none","Rationale":"r","Required-changes":"none","Escalation":"none","Ledger":"l"}\n' "$(printf 'a%.0s' $(seq 1 64))" > "$TMPF/resp2.json"
  META2=$(run --resume "$TMPF/resp2.json" "$RD" "$CTX" 01 01-1-2 artifact.md routine 2>/dev/null) || { echo "FAIL: bare verdict resume failed"; exit 1; }
  printf '%s' "$META2" | jq -e '.hash_match == false' >/dev/null || { echo "FAIL: hash mismatch not reported"; exit 1; }
  jq -e '(has("usage") | not) and (._note | test("no usage"))' "$(printf '%s' "$META2" | jq -r .envelope_path)" >/dev/null \
    || { echo "FAIL: absent usage was fabricated"; exit 1; }
  grep -q 'does NOT match the staged artifact digest' "$RD/log.md" || { echo "FAIL: FR9 warning not logged"; exit 1; }
  echo PASS
expected: exit 0; stdout "PASS". Phase 1 exits 2, prints the plan, stages artifact.sha256, writes no verdict. --resume refuses (exit 1, nothing durable, plan unconsumed, no temp files) a verdict missing a field, carrying an extra key, a bad Decision, a malformed hash, non-JSON, a spawn with no plan, a staged artifact whose digest no longer matches the plan, and any non-cursor host. A good response yields exit 0, the same meta JSON as other hosts plus plan_path, a schema-normalized verdict (null Integration-evidence dropped), a Claude-shaped envelope with normalized usage, events/raw files, the plan marked resumed with the response digest, an audit line, and an envelope append-reviewer-tokens.sh accepts. A second resume of the same spawn is refused, as is re-planning a resumed spawn (its outputs untouched). Of two concurrent resumes of one plan exactly one publishes and the loser leaves no claim. A stale claim is refused with a recovery hint and clears on removal. An interrupted resume completes on replay with the same response whatever link it died after (raw is published first; missing outputs are republished, existing ones verified byte-for-byte, the audit line of record written once), is refused with a different response, never replaces a published output that no longer matches, and refuses output that has no raw response behind it. A bare verdict without usage yields an envelope with a _note and no usage block; a wrong Artifact-hash is reported as hash_match false and logged, as on other hosts. Mutation: delete the plan-status check → double resume passes; delete the mkdir claim → the stale-claim case publishes instead of being refused; publish the raw last instead of first → the raw-only-crash replay case is refused; drop the cmp in publish_exclusive → the tampered-output case passes; replace the plan's `ln` with `mv -f` → re-planning a resumed spawn passes; delete validate_verdict_against_schema → extra-key passes; drop the artifactSha256 binding → the changed-artifact case passes; drop the `+ (if $usage == null …)` branch → the bare-verdict envelope gains fabricated zeros.
