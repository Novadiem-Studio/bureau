name: post-hoc fragment validation rejects exact-zero wash at both accounting seams
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  trap 'rm -rf "$TMPF"' EXIT INT TERM
  RUN_PATH="$TMPF/20260813-fragment-validation"
  CONTEXT_RUN="$TMPF/20260813-fragment-context"
  IDENTITY_RUN="$TMPF/20260813-fragment-identities"
  ALIAS_RUN="$TMPF/20260813-fragment-alias"
  AGENT_RUN="$TMPF/20260813-fragment-agents"
  CONDUCTOR_RUN="$TMPF/20260813-fragment-conductors"
  NO_DELEGATE_RUN="$TMPF/20260813-fragment-no-delegate"
  LEGACY_DELEGATE_RUN="$TMPF/20260813-fragment-legacy-delegate"
  HARNESS="$TMPF/harness"
  mkdir -p "$RUN_PATH" "$CONTEXT_RUN" "$IDENTITY_RUN" "$ALIAS_RUN" "$AGENT_RUN" \
    "$CONDUCTOR_RUN" "$NO_DELEGATE_RUN" "$LEGACY_DELEGATE_RUN" "$HARNESS"
  printf '%s\n' '{"workflow":"feature","phases_complete":[],"phase_status":"complete","critic_loops":{"architect":1}}' > "$RUN_PATH/state.json"
  : > "$RUN_PATH/log.md"
  for run_path in "$CONTEXT_RUN" "$IDENTITY_RUN" "$ALIAS_RUN" "$AGENT_RUN" "$CONDUCTOR_RUN" \
    "$NO_DELEGATE_RUN" "$LEGACY_DELEGATE_RUN"; do
    cp "$RUN_PATH/state.json" "$run_path/state.json"
  done
  for run_path in "$RUN_PATH" "$CONTEXT_RUN" "$IDENTITY_RUN" "$ALIAS_RUN" "$AGENT_RUN"; do
    printf '%s\n' '{"delegate_session_id":"delegate-a","conductor_agent_id":"cond-a","conductor_agent_ids":["cond-a"]}' > "$run_path/delegate-state.json"
  done
  printf '%s\n' '{"delegate_session_id":"delegate-conductors","conductor_agent_id":"cond-a","conductor_agent_ids":["cond-a","cond-b"]}' \
    > "$CONDUCTOR_RUN/delegate-state.json"
  : > "$CONDUCTOR_RUN/log.md"
  for run_path in "$NO_DELEGATE_RUN" "$LEGACY_DELEGATE_RUN"; do
    printf '%s\n' '{"conductor_agent_id":"cond-a","conductor_agent_ids":["cond-a"]}' > "$run_path/delegate-state.json"
  done
  : > "$NO_DELEGATE_RUN/log.md"
  printf '%s\n' 'DELEGATE-TOKEN-EVENT: {"session_id":"legacy-delegate-session","final":true}' \
    > "$LEGACY_DELEGATE_RUN/log.md"
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"analyst-1","status":"started","at":"2026-08-13T00:00:00Z"}' \
    > "$CONTEXT_RUN/log.md"
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"analyst-missing-1","status":"started","at":"2026-08-13T00:00:00Z"}' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-collision-1","status":"started","at":"2026-08-13T00:00:01Z"}' \
    > "$IDENTITY_RUN/log.md"
  printf '%s\n' \
    'SPAWN-EVENT: role=critic agent=challenger configured_model=opus actual_model=opus attempt=1 attempt_id=challenger-1 status=started at=2026-08-13T00:00:00Z' \
    > "$ALIAS_RUN/log.md"
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"analyst","agent":"Analizer 2000","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"analyst-agent-1","status":"started","at":"2026-08-13T00:00:00Z"}' \
    'SPAWN-EVENT: {"role":"architect","agent":"The Architect","configured_model":"opus","actual_model":"opus","attempt":1,"attempt_id":"architect-agent-1","status":"started","at":"2026-08-13T00:00:01Z"}' \
    > "$AGENT_RUN/log.md"

  # account-run resolves both consumers beside itself. The hermetic aggregator
  # stub returns exactly the candidate fragment selected by each case.
  cp "$ROOT/scripts/account-run.sh" "$ROOT/scripts/account-tokens.sh" "$HARNESS/"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    '[ -n "${POSTHOC_FIXTURE_FILE:-}" ] && [ -r "$POSTHOC_FIXTURE_FILE" ] || exit 1' \
    '/bin/cat "$POSTHOC_FIXTURE_FILE"' \
    > "$HARNESS/aggregate-transcripts.sh"
  chmod +x "$HARNESS/account-run.sh" "$HARNESS/account-tokens.sh" "$HARNESS/aggregate-transcripts.sh"

  ZERO='{"input":0,"cache_creation":0,"cache_read":0,"processed":0,"output":0}'
  jq -cn --argjson zero "$ZERO" '
    {delegate:{tokens:$zero,turns:0,confidence:"exact"},
     conductor:{tokens:$zero,turns:0,legs:1,confidence:"exact"},
     specialists:[]}
  ' > "$TMPF/valid-zero.json"
  jq '.delegate.confidence = "unavailable" | .delegate._note = "Delegate identity absent"' \
    "$TMPF/valid-zero.json" > "$TMPF/delegate-unavailable.json"

  : > "$TMPF/empty-document.json"
  printf '%s\n' '{}' > "$TMPF/empty-object.json"
  printf '%s\n' '{"delegate":' > "$TMPF/malformed-json.json"
  jq -c '.' "$TMPF/valid-zero.json" > "$TMPF/multiple-documents.json"
  jq -c '.' "$TMPF/valid-zero.json" >> "$TMPF/multiple-documents.json"
  jq '._runtime_gap = "openai — no Claude JSONL"' "$TMPF/valid-zero.json" > "$TMPF/runtime-gap-valid-shape.json"
  jq '.delegate.tokens = {}' "$TMPF/valid-zero.json" > "$TMPF/empty-token-fields.json"
  jq '.conductor.tokens.input = "0"' "$TMPF/valid-zero.json" > "$TMPF/nonnumeric-token.json"
  jq '.conductor.tokens.input = -1 | .conductor.tokens.processed = -1' "$TMPF/valid-zero.json" > "$TMPF/negative-token.json"
  jq '.conductor.tokens.input = 1 | .conductor.tokens.processed = 0' "$TMPF/valid-zero.json" > "$TMPF/processed-inconsistent.json"
  jq '.delegate.turns = 0.5' "$TMPF/valid-zero.json" > "$TMPF/fractional-turns.json"
  jq '.delegate.confidence = "certain"' "$TMPF/valid-zero.json" > "$TMPF/bad-confidence.json"
  jq '.conductor.legs = -1' "$TMPF/valid-zero.json" > "$TMPF/negative-legs.json"
  jq '.conductor.legs = 0' "$TMPF/valid-zero.json" > "$TMPF/impossible-exact-zero-legs.json"
  jq '.delegate.confidence = "estimated"' "$TMPF/valid-zero.json" > "$TMPF/impossible-delegate-confidence.json"
  jq '.conductor.confidence = "suspect" | .conductor._note = "impossible top-level disposition"' \
    "$TMPF/valid-zero.json" > "$TMPF/impossible-conductor-confidence.json"
  jq '.delegate.confidence = "partial"' "$TMPF/valid-zero.json" > "$TMPF/note-free-partial-delegate.json"
  jq '.conductor.confidence = "unavailable"' "$TMPF/valid-zero.json" > "$TMPF/note-free-unavailable-conductor.json"
  jq '.delegate.confidence = "unavailable" | .delegate._note = "gap" | .delegate.tokens.input = 1 | .delegate.tokens.processed = 1' \
    "$TMPF/valid-zero.json" > "$TMPF/nonzero-unavailable-delegate.json"
  jq --argjson zero "$ZERO" '.specialists = [
    {attempt_id:null,role:null,agent_id:"agent-u",tokens:$zero,turns:0,confidence:"exact"}
  ]' "$TMPF/valid-zero.json" > "$TMPF/exact-null-attempt.json"

  jq --argjson zero "$ZERO" '.specialists = [
    {attempt_id:"analyst-1",role:"analyst",agent_id:"analyst-a",tokens:$zero,turns:0,confidence:"exact"}
  ]' "$TMPF/valid-zero.json" > "$TMPF/context-valid.json"
  jq '.specialists = []' "$TMPF/context-valid.json" > "$TMPF/context-missing-attempt.json"
  jq '.specialists[0].role = "architect"' "$TMPF/context-valid.json" > "$TMPF/context-role-mismatch.json"
  jq '.specialists[0].role = null' "$TMPF/context-valid.json" > "$TMPF/context-bad-role.json"
  jq '.specialists[0].agent_id = null' "$TMPF/context-valid.json" > "$TMPF/context-undocumented-null-agent.json"
  jq '.specialists += [(.specialists[0] | .agent_id = "analyst-b")]' \
    "$TMPF/context-valid.json" > "$TMPF/context-duplicate-attempt.json"
  jq --argjson zero "$ZERO" '.specialists += [
    {attempt_id:"mage-1",role:"mage",agent_id:"mage-a",tokens:$zero,turns:0,confidence:"exact"}
  ]' "$TMPF/context-valid.json" > "$TMPF/context-unexpected-attempt.json"
  jq '.specialists[0].confidence = "estimated" | .specialists[0]._note = "impossible attributed disposition"' \
    "$TMPF/context-valid.json" > "$TMPF/context-attributed-estimated.json"
  jq '.specialists[0].confidence = "inferred" | .specialists[0]._note = "impossible attributed disposition"' \
    "$TMPF/context-valid.json" > "$TMPF/context-attributed-inferred.json"
  jq '.specialists[0].confidence = "partial"' \
    "$TMPF/context-valid.json" > "$TMPF/context-note-free-partial.json"
  jq '.specialists[0].confidence = "unavailable"' \
    "$TMPF/context-valid.json" > "$TMPF/context-note-free-unavailable.json"
  jq '.specialists[0].confidence = "suspect" | .specialists[0]._note = "null agent required"' \
    "$TMPF/context-valid.json" > "$TMPF/context-suspect-with-agent.json"
  jq '.specialists[0].confidence = "unavailable" | .specialists[0]._note = "gap" | .specialists[0].tokens.input = 1 | .specialists[0].tokens.processed = 1' \
    "$TMPF/context-valid.json" > "$TMPF/context-nonzero-unavailable.json"

  jq --argjson zero "$ZERO" '.specialists = [
    {attempt_id:"challenger-1",role:"critic",agent_id:"challenger-a",tokens:$zero,turns:0,confidence:"exact"}
  ]' "$TMPF/valid-zero.json" > "$TMPF/alias-valid.json"
  jq --argjson zero "$ZERO" '.specialists = [
    {attempt_id:"analyst-agent-1",role:"analyst",agent_id:"agent-a",tokens:$zero,turns:0,confidence:"exact"},
    {attempt_id:"architect-agent-1",role:"architect",agent_id:"agent-b",tokens:$zero,turns:0,confidence:"exact"}
  ]' "$TMPF/valid-zero.json" > "$TMPF/agents-valid.json"
  jq '.specialists[1].agent_id = "agent-a"' \
    "$TMPF/agents-valid.json" > "$TMPF/duplicate-agent-id.json"
  jq '.conductor.legs = 2' "$TMPF/valid-zero.json" > "$TMPF/conductors-valid.json"
  jq '.conductor.legs = 1' "$TMPF/conductors-valid.json" > "$TMPF/conductors-exact-under-count.json"
  jq '.conductor.legs = 3' "$TMPF/conductors-valid.json" > "$TMPF/conductors-exact-over-count.json"
  jq '.conductor.legs = 1 | .conductor.confidence = "partial" | .conductor._note = "one leg incomplete"' \
    "$TMPF/conductors-valid.json" > "$TMPF/conductors-partial-under-count.json"
  jq '.conductor.legs = 1 | .conductor.confidence = "unavailable" | .conductor._note = "transcripts missing"' \
    "$TMPF/conductors-valid.json" > "$TMPF/conductors-unavailable-under-count.json"
  jq --argjson zero "$ZERO" '.specialists = [
    {attempt_id:null,role:null,agent_id:"unattributed-note-free",tokens:$zero,turns:0,confidence:"inferred"}
  ]' "$TMPF/valid-zero.json" > "$TMPF/note-free-unattributed.json"
  jq --argjson zero "$ZERO" '.specialists = [
    {attempt_id:null,role:null,agent_id:"unattributed-nonzero",tokens:($zero + {input:1,processed:1}),turns:0,confidence:"unavailable",_note:"gap"}
  ]' "$TMPF/valid-zero.json" > "$TMPF/nonzero-unavailable-unattributed.json"

  assert_rejected_at_both_seams() {
    candidate="$1"
    candidate_run="${2:-$RUN_PATH}"
    direct=$(bash "$ROOT/scripts/account-tokens.sh" "$candidate_run" "$candidate") || return 1
    printf '%s' "$direct" | jq -e '
      .tokens.processed_total == ({value:0,confidence:"unavailable"}
        + {_note:.tokens.processed_total._note,_semantics:.tokens.processed_total._semantics})
      and (.tokens.processed_total._note | contains("no post-hoc aggregator fragment"))
      and .tokens.output_total.value == 0
      and .tokens.output_total.confidence == "unavailable"
      and .tokens.tokens_per_loop.value == null
      and .tokens.tokens_per_loop.confidence == "unavailable"
    ' >/dev/null || return 1

    rm -f "$candidate_run/accounting.json"
    POSTHOC_FIXTURE_FILE="$candidate" NOVADIEM_USAGE_SNAPSHOT_PATH="$TMPF/no-snapshot" \
      bash "$HARNESS/account-run.sh" "$candidate_run" >/dev/null 2>&1 || return 1
    jq -e '
      .schema_version == 1
      and (has("_posthoc") | not)
      and (has("conductor_tokens") | not)
      and (has("delegate_tokens") | not)
      and (has("tokens") | not)
    ' "$candidate_run/accounting.json" >/dev/null || return 1
  }

  assert_accepted_at_both_seams() {
    candidate="$1"
    candidate_run="$2"
    expected_confidence="$3"
    direct=$(bash "$ROOT/scripts/account-tokens.sh" "$candidate_run" "$candidate") || return 1
    printf '%s' "$direct" | jq -e --arg confidence "$expected_confidence" '
      .tokens.processed_total.value == 0
      and .tokens.processed_total.confidence == $confidence
      and .tokens.output_total.confidence == "estimated"
    ' >/dev/null || return 1
    rm -f "$candidate_run/accounting.json"
    POSTHOC_FIXTURE_FILE="$candidate" NOVADIEM_USAGE_SNAPSHOT_PATH="$TMPF/no-snapshot" \
      bash "$HARNESS/account-run.sh" "$candidate_run" >/dev/null 2>&1 || return 1
    jq -e --arg confidence "$expected_confidence" '
      .schema_version == 2
      and (._posthoc | type) == "object"
      and .tokens.processed_total.value == 0
      and .tokens.processed_total.confidence == $confidence
    ' "$candidate_run/accounting.json" >/dev/null || return 1
  }

  for candidate in \
    "$TMPF/empty-document.json" \
    "$TMPF/empty-object.json" \
    "$TMPF/malformed-json.json" \
    "$TMPF/multiple-documents.json" \
    "$TMPF/runtime-gap-valid-shape.json" \
    "$TMPF/empty-token-fields.json" \
    "$TMPF/nonnumeric-token.json" \
    "$TMPF/negative-token.json" \
    "$TMPF/processed-inconsistent.json" \
    "$TMPF/fractional-turns.json" \
    "$TMPF/bad-confidence.json" \
    "$TMPF/negative-legs.json" \
    "$TMPF/impossible-exact-zero-legs.json" \
    "$TMPF/impossible-delegate-confidence.json" \
    "$TMPF/impossible-conductor-confidence.json" \
    "$TMPF/note-free-partial-delegate.json" \
    "$TMPF/note-free-unavailable-conductor.json" \
    "$TMPF/nonzero-unavailable-delegate.json" \
    "$TMPF/exact-null-attempt.json" \
    "$TMPF/note-free-unattributed.json" \
    "$TMPF/nonzero-unavailable-unattributed.json"
  do
    assert_rejected_at_both_seams "$candidate" || {
      echo "FAIL: unusable fragment crossed an accounting seam: $(basename "$candidate")"
      exit 1
    }
  done

  for candidate in \
    "$TMPF/context-missing-attempt.json" \
    "$TMPF/context-role-mismatch.json" \
    "$TMPF/context-bad-role.json" \
    "$TMPF/context-undocumented-null-agent.json" \
    "$TMPF/context-duplicate-attempt.json" \
    "$TMPF/context-unexpected-attempt.json" \
    "$TMPF/context-attributed-estimated.json" \
    "$TMPF/context-attributed-inferred.json" \
    "$TMPF/context-note-free-partial.json" \
    "$TMPF/context-note-free-unavailable.json" \
    "$TMPF/context-suspect-with-agent.json" \
    "$TMPF/context-nonzero-unavailable.json"
  do
    assert_rejected_at_both_seams "$candidate" "$CONTEXT_RUN" || {
      echo "FAIL: context-invalid fragment crossed an accounting seam: $(basename "$candidate")"
      exit 1
    }
  done
  assert_rejected_at_both_seams "$TMPF/duplicate-agent-id.json" "$AGENT_RUN" || {
    echo "FAIL: duplicate transcript identity crossed an accounting seam"
    exit 1
  }
  for candidate in \
    "$TMPF/conductors-exact-under-count.json" \
    "$TMPF/conductors-exact-over-count.json" \
    "$TMPF/conductors-partial-under-count.json" \
    "$TMPF/conductors-unavailable-under-count.json"
  do
    assert_rejected_at_both_seams "$candidate" "$CONDUCTOR_RUN" || {
      echo "FAIL: impossible Conductor leg count crossed an accounting seam: $(basename "$candidate")"
      exit 1
    }
  done
  assert_rejected_at_both_seams "$TMPF/valid-zero.json" "$NO_DELEGATE_RUN" || {
    echo "FAIL: exact Delegate crossed an accounting seam without recoverable identity"
    exit 1
  }

  # A structurally complete numeric zero is real evidence and remains usable.
  direct=$(bash "$ROOT/scripts/account-tokens.sh" "$RUN_PATH" "$TMPF/valid-zero.json") || exit 1
  printf '%s' "$direct" | jq -e '
    .tokens.processed_total.value == 0
    and .tokens.processed_total.confidence == "exact"
    and .tokens.output_total.value == 0
    and .tokens.output_total.confidence == "estimated"
    and .tokens.tokens_per_loop.value == 0
    and .tokens.tokens_per_loop.confidence == "exact"
  ' >/dev/null || exit 1
  rm -f "$RUN_PATH/accounting.json"
  POSTHOC_FIXTURE_FILE="$TMPF/valid-zero.json" NOVADIEM_USAGE_SNAPSHOT_PATH="$TMPF/no-snapshot" \
    bash "$HARNESS/account-run.sh" "$RUN_PATH" >/dev/null 2>&1 || exit 1
  jq -e --argjson zero "$ZERO" '
    .schema_version == 2
    and .delegate_tokens == {tokens:$zero,turns:0,confidence:"exact"}
    and .conductor_tokens == {tokens:$zero,turns:0,legs:1,confidence:"exact"}
    and .tokens.processed_total.value == 0
    and .tokens.processed_total.confidence == "exact"
    and (._posthoc.run_ended_at | type) == "string"
  ' "$RUN_PATH/accounting.json" >/dev/null || exit 1

  # Context membership and persona/cast aliases are valid controls, not casualties
  # of the exact-wash guard. The alias run uses the accepted historical key=value form.
  assert_accepted_at_both_seams "$TMPF/context-valid.json" "$CONTEXT_RUN" "exact" || exit 1
  assert_accepted_at_both_seams "$TMPF/alias-valid.json" "$ALIAS_RUN" "exact" || exit 1
  assert_accepted_at_both_seams "$TMPF/agents-valid.json" "$AGENT_RUN" "exact" || exit 1
  assert_accepted_at_both_seams "$TMPF/conductors-valid.json" "$CONDUCTOR_RUN" "exact" || exit 1
  assert_accepted_at_both_seams "$TMPF/delegate-unavailable.json" "$NO_DELEGATE_RUN" "exact" || exit 1
  assert_accepted_at_both_seams "$TMPF/valid-zero.json" "$LEGACY_DELEGATE_RUN" "exact" || exit 1

  # Preserve the documented identity allowances used by real degraded output.
  jq --argjson zero "$ZERO" '.specialists = [
    {attempt_id:"analyst-missing-1",role:"analyst",agent_id:null,tokens:$zero,turns:0,confidence:"unavailable",_note:"transcript missing"},
    {attempt_id:"architect-collision-1",role:"architect",agent_id:null,tokens:$zero,turns:0,confidence:"suspect",_note:"attempt-id collision"},
    {attempt_id:null,role:null,agent_id:"unattributed",tokens:$zero,turns:0,confidence:"inferred",_note:"counted as unattributed"},
    {attempt_id:null,role:null,agent_id:"unattributed-gap",tokens:$zero,turns:0,confidence:"unavailable",_note:"unattributed transcript unusable"}
  ]' "$TMPF/valid-zero.json" > "$TMPF/valid-degraded-identities.json"
  direct=$(bash "$ROOT/scripts/account-tokens.sh" "$IDENTITY_RUN" "$TMPF/valid-degraded-identities.json") || exit 1
  printf '%s' "$direct" | jq -e '
    .tokens.processed_total.confidence == "partial"
    and (.tokens.unattributed_records | length) == 2
  ' >/dev/null || exit 1
  rm -f "$IDENTITY_RUN/accounting.json"
  POSTHOC_FIXTURE_FILE="$TMPF/valid-degraded-identities.json" NOVADIEM_USAGE_SNAPSHOT_PATH="$TMPF/no-snapshot" \
    bash "$HARNESS/account-run.sh" "$IDENTITY_RUN" >/dev/null 2>&1 || exit 1
  jq -e '.schema_version == 2 and (._posthoc | type) == "object"' "$IDENTITY_RUN/accounting.json" >/dev/null || exit 1

  echo PASS
  # Mutations: restore either shallow tokens-object gate, multi-document parsing,
  # zero-/miscounted-leg exactness, identity-free Delegate exactness, loose
  # confidence/identity/prefix rules, duplicate attempt/agent membership, or omit contextual
  # attempt equality and at least one invalid fragment becomes schema 2.
  # Reject all zeroes/aliases/documented null identities and an accepted control fails.
expected: exit 0; stdout "PASS"; both fragment seams reject empty, malformed, runtime-gated, inconsistent, negative, non-integer, impossible confidence/identity/membership shapes, identity-free Delegate exactness, duplicate transcript identities, and omitted/miscounted Conductor legs while accepting complete zero with recorded or legacy Delegate identity, unavailable identity gaps, context-complete aliases, exact recorded-leg controls, and documented degraded identities
phase: integration hardening
owner: post-hoc close-out trust boundary
