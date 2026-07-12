name: class-closure Guard 1 (no emitter attributes a foreigner) — every TRANSCRIPT-READING token emitter (E1 conductor-stop, E2/E2b subagent-stop conductor branch, E3 subagent-stop specialist branch) driven with a FOREIGN identity emits ZERO attribution and still exits 0; E2b covers the Step 8.0 S3 edge (topology=integrated but no conductor_agent_id → fail-closed); E4 (reviewer) is OUT of scope by construction (caller-attested, reads no transcript)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); trap 'rm -rf "$TMPF"' EXIT

  # ── CLASS FRAMING (read before adding a token emitter) ────────────────────────
  # This is the CLASS guard for ownership class 1 ("ownership-by-mention": a foreign
  # same-machine session that echoed/quoted the spawn prompt gets its tokens
  # attributed to this run). It is the ENUMERATED SET of transcript-reading token
  # emitters, each proven to REJECT a foreigner. It is NOT a copy of the per-instance
  # fixtures 67/167/163 — its value is the emitter-keyed framing: a NEW transcript-
  # reading hook emitter added without an ownership gate MUST get a row here, or the
  # security property (no emitter attributes a foreigner) is unproven for it.
  #
  # THE THREE TRANSCRIPT-READING EMITTERS and the credential each foreign-drive strips:
  #   E1  conductor-stop.sh          — secret run nonce in transcript (Steps A.5-C.0)
  #   E2  subagent-stop.sh conductor — agent_id == delegate-state#conductor_agent_id (Step 8.0 S1)
  #   E2b subagent-stop.sh conductor — S3: topology=integrated but NO conductor_agent_id → fail-closed (Step 8.0 S3)
  #   E3  subagent-stop.sh spawn     — secret run nonce in transcript (Step 4.7)
  #
  # E4 (append-reviewer-tokens.sh, REVIEWER-TOKEN-EVENT) is OUT of scope BY
  # CONSTRUCTION: it reads NO foreign transcript and cannot self-classify — it is
  # Delegate-driven and caller-attested (its ownership lives at the Delegate call-site,
  # agents/delegate.md, not in the helper). There is no foreign transcript to feed it,
  # so it correctly has no row here. Its # OWNERSHIP-GATE: none-self marker documents
  # this. If a future maintainer adds a self-classifying (transcript-reading) branch to
  # append-reviewer-tokens.sh, that branch becomes E5 and MUST get a row here.
  #
  # IF YOU ADD A TRANSCRIPT-READING EMITTER: add a sub-case below that drives it with a
  # foreign identity (the missing/wrong credential its gate checks) and asserts ZERO
  # attribution + hook exit 0.

  fail() { echo "FAIL: $*"; exit 1; }

  # ── E3 foreign (specialist, wrong/absent run nonce) ───────────────────────────
  # Pointer present with secret nonce N; the foreign transcript echoes RUN_DIR +
  # Attempt ID (the ownership-by-mention vector) but NOT N. Step 4.7 must reject.
  RUN_E3="$TMPF/e3-run"; mkdir -p "$RUN_E3"; touch "$RUN_E3/log.md"
  E3_PTR="$TMPF/e3-active-runs"; mkdir -p "$E3_PTR"
  N3="secret-nonce-e3-only-owner-$(date +%s)"
  PK3=$(printf '%s' "$RUN_E3" | sed 's#[/.]#-#g')
  printf '{"run_dir":"%s","nonce":"%s","written_at":"2026-07-11T00:00:00Z","project_dir":"%s"}\n' \
    "$RUN_E3" "$N3" "$TMPF" > "$E3_PTR/$PK3"
  jq -cn --arg rp "$RUN_E3" \
    '{"type":"user","message":{"role":"user","content":("RUN_DIR: " + $rp + "\nAttempt ID: mage-1\n(quoted the spawn prompt; no nonce)\n")}}' \
    > "$TMPF/e3.jsonl"
  printf '%s\n' \
    '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":9999,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":500},"content":[{"type":"text"}]}}' \
    >> "$TMPF/e3.jsonl"
  echo '{"agent_transcript_path":"'"$TMPF/e3.jsonl"'","agent_id":"agent-foreign-e3"}' \
    | BUREAU_POINTER_DIR="$E3_PTR" bash "$ROOT/scripts/subagent-stop.sh" 2>/dev/null
  rc=$?; [ "$rc" = "0" ] || fail "E3 hook exited $rc (must be 0)"
  n=$(grep -c "^SPAWN-TOKEN-EVENT:" "$RUN_E3/log.md" 2>/dev/null); n=${n:-0}
  [ "$n" = "0" ] || { cat "$RUN_E3/log.md"; fail "E3 foreign attributed — $n SPAWN-TOKEN-EVENT (expected 0)"; }

  # ── E2 foreign (v2 conductor branch, wrong agent_id) ──────────────────────────
  # delegate-state.json names the REAL conductor agent-REAL; the foreign transcript
  # carries the PUBLIC BUREAU_ROLE: conductor marker + RUN_DIR but its agent_id !=
  # conductor_agent_id. Step 8.0 must reject as NEITHER conductor NOR specialist.
  RUN_E2="$TMPF/e2-run"; mkdir -p "$RUN_E2"; touch "$RUN_E2/log.md"
  echo '{"accounting":{"status":"complete"}}' > "$RUN_E2/state.json"
  echo '{"topology":"integrated","conductor_agent_id":"agent-REAL","active_checkpoint":"01","revise_counts":{},"revision_cap":2}' > "$RUN_E2/delegate-state.json"
  jq -cn --arg rp "$RUN_E2" \
    '{"type":"user","message":{"role":"user","content":("RUN_DIR: " + $rp + "\ntopology: integrated\nBUREAU_ROLE: conductor\n")}}' \
    > "$TMPF/e2.jsonl"
  printf '%s\n' \
    '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":9999,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":500},"content":[{"type":"tool_use"}]}}' \
    >> "$TMPF/e2.jsonl"
  echo '{"agent_transcript_path":"'"$TMPF/e2.jsonl"'","agent_id":"agent-FOREIGN"}' \
    | bash "$ROOT/scripts/subagent-stop.sh" 2>/dev/null
  rc=$?; [ "$rc" = "0" ] || fail "E2 hook exited $rc (must be 0)"
  cn=$(grep -c "^CONDUCTOR-TOKEN-EVENT:" "$RUN_E2/log.md" 2>/dev/null); cn=${cn:-0}
  sn=$(grep -c "^SPAWN-TOKEN-EVENT:" "$RUN_E2/log.md" 2>/dev/null); sn=${sn:-0}
  [ "$cn" = "0" ] || { cat "$RUN_E2/log.md"; fail "E2 foreign attributed as Conductor — $cn CONDUCTOR-TOKEN-EVENT (expected 0)"; }
  [ "$sn" = "0" ] || { cat "$RUN_E2/log.md"; fail "E2 foreign fell through to specialist — $sn SPAWN-TOKEN-EVENT (expected 0)"; }

  # ── E2b foreign (v2 conductor branch, topology=integrated, NO credential) ─────
  # E2 above always supplied conductor_agent_id (exercises Step 8.0 S1 reject). It
  # does NOT exercise S3 — an integrated run MISSING the credential with a foreigner
  # presenting the public marker. Here delegate-state.json declares integrated but
  # OMITS conductor_agent_id (a write-ordering gap). A foreign transcript carries the
  # PUBLIC BUREAU_ROLE: conductor marker + RUN_DIR. Step 8.0 State S3 must FAIL-CLOSED:
  # neither CONDUCTOR nor SPAWN attribution, hook exit 0. (The class guard missed this
  # because E2 always supplied a credential — S3 was unenumerated.)
  RUN_E2B="$TMPF/e2b-run"; mkdir -p "$RUN_E2B"; touch "$RUN_E2B/log.md"
  echo '{"accounting":{"status":"complete"}}' > "$RUN_E2B/state.json"
  echo '{"topology":"integrated","active_checkpoint":"01","revise_counts":{},"revision_cap":2}' > "$RUN_E2B/delegate-state.json"   # NOTE: no conductor_agent_id
  jq -cn --arg rp "$RUN_E2B" \
    '{"type":"user","message":{"role":"user","content":("RUN_DIR: " + $rp + "\ntopology: integrated\nBUREAU_ROLE: conductor\n")}}' \
    > "$TMPF/e2b.jsonl"
  printf '%s\n' \
    '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":9999,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":500},"content":[{"type":"tool_use"}]}}' \
    >> "$TMPF/e2b.jsonl"
  echo '{"agent_transcript_path":"'"$TMPF/e2b.jsonl"'","agent_id":"agent-FOREIGN-e2b"}' \
    | bash "$ROOT/scripts/subagent-stop.sh" 2>/dev/null
  rc=$?; [ "$rc" = "0" ] || fail "E2b hook exited $rc (must be 0)"
  cn=$(grep -c "^CONDUCTOR-TOKEN-EVENT:" "$RUN_E2B/log.md" 2>/dev/null); cn=${cn:-0}
  sn=$(grep -c "^SPAWN-TOKEN-EVENT:" "$RUN_E2B/log.md" 2>/dev/null); sn=${sn:-0}
  [ "$cn" = "0" ] || { cat "$RUN_E2B/log.md"; fail "E2b integrated-no-credential foreigner attributed as Conductor — $cn CONDUCTOR-TOKEN-EVENT (expected 0)"; }
  [ "$sn" = "0" ] || { cat "$RUN_E2B/log.md"; fail "E2b foreigner fell through to specialist — $sn SPAWN-TOKEN-EVENT (expected 0)"; }

  # ── E1 foreign (top-session conductor/delegate, mention-only, absent nonce) ───
  # The OWNER's live run: a real run dir with log.md, enrolled in the pointer with its
  # secret nonce N (the public run_dir path is mentionable; the nonce is NOT). The
  # foreign transcript ECHOES the owner's run_dir (the ownership-by-mention vector) but
  # does NOT carry N. Steps A.5-C ownership-select require BOTH the nonce AND the
  # run_dir grep, so the mention-only foreigner is NOT selected → NOTHING is appended to
  # the owner's log.md → hook exit 0. (Emit, if it fired, would land on the SELECTED
  # pointer's RUN_DIR = the owner's log — so that is where we assert zero.)
  RUN_E1="$TMPF/e1-owner"; mkdir -p "$RUN_E1"; touch "$RUN_E1/log.md"
  echo '{"accounting":{"status":"complete","path":"accounting.json"}}' > "$RUN_E1/state.json"
  export BUREAU_POINTER_FILE="$TMPF/e1-active-run"
  N1="secret-nonce-e1-owner-only-has-this-$(date +%s)"
  echo '{"run_dir":"'"$RUN_E1"'","nonce":"'"$N1"'","written_at":"2026-07-11T00:00:01Z"}' \
    > "$BUREAU_POINTER_FILE"
  # FOREIGN transcript: mentions the owner's RUN_DIR (echo-able) but NOT the secret nonce.
  printf '%s\n' "RUN_DIR: $RUN_E1" "(quoted the run dir from a shared log; no nonce)" > "$TMPF/e1.jsonl"
  printf '%s\n' \
    '{"type":"assistant","message":{"id":"msg-A","usage":{"input_tokens":9999,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":500},"content":[{"type":"text"}]}}' \
    >> "$TMPF/e1.jsonl"
  echo '{"session_id":"sess-foreign","transcript_path":"'"$TMPF/e1.jsonl"'","stop_hook_active":false}' \
    | bash "$ROOT/scripts/conductor-stop.sh" 2>/dev/null
  rc=$?; [ "$rc" = "0" ] || fail "E1 hook exited $rc (must be 0)"
  e1c=$(grep -c "^CONDUCTOR-TOKEN-EVENT:" "$RUN_E1/log.md" 2>/dev/null); e1c=${e1c:-0}
  e1d=$(grep -c "^DELEGATE-TOKEN-EVENT:" "$RUN_E1/log.md" 2>/dev/null); e1d=${e1d:-0}
  [ "$e1c" = "0" ] || { cat "$RUN_E1/log.md"; fail "E1 mention-only foreigner attributed as Conductor — $e1c CONDUCTOR-TOKEN-EVENT (expected 0)"; }
  [ "$e1d" = "0" ] || { cat "$RUN_E1/log.md"; fail "E1 mention-only foreigner attributed as Delegate — $e1d DELEGATE-TOKEN-EVENT (expected 0)"; }
  unset BUREAU_POINTER_FILE

  echo "PASS"
  # Mutation note (per-emitter, the CORE security proofs — same three the per-instance
  # fixtures 163/167/67 document, re-expressed here as one emitter-keyed CLASS check):
  #  E3: delete the Step 4.7 `grep -qF -- "$nonce"` rejection (or fall through to
  #      attribute when the nonce is absent) → the mention-only foreigner emits a
  #      SPAWN-TOKEN-EVENT → E3 assertion fails.
  #  E2: delete the Step 8.0 identity gate (the agent_id != conductor_agent_id reject)
  #      → the foreigner is attributed as the Conductor → E2 assertion fails.
  #  E2b: delete the S3 `elif [ "$_cond_topology" = "integrated" ]` fail-closed arm
  #      → the integrated-no-credential foreigner falls to the S2 marker fail-open →
  #      it is attributed by the public BUREAU_ROLE marker → E2b assertion fails.
  #  E1: neutralize the Steps A.5-C ownership-select nonce match → the foreigner's
  #      transcript emits a CONDUCTOR/DELEGATE-TOKEN-EVENT → E1 assertion fails.
  # Neutralizing ANY ONE emitter's gate makes THAT emitter's foreign attribution
  # appear and fails this fixture — the all-emitters class property.
expected: exit 0; stdout "PASS"; each of the three transcript-reading token emitters (E1 conductor-stop, E2/E2b subagent-stop conductor branch, E3 subagent-stop specialist branch), driven with a foreign identity (wrong/absent nonce for E1/E3; agent_id != conductor_agent_id for E2; topology=integrated with NO conductor_agent_id for E2b), emits ZERO attribution and still exits 0. E4 (reviewer) is out of scope by construction (reads no transcript). Mutation-test: neutralizing any one emitter's ownership gate — including deleting the Step 8.0 S3 fail-closed arm — re-attributes that foreigner and fails this fixture.
phase: 04 · feature — class-closure Guard 1 (no emitter attributes a foreigner meta-fixture)
owner: conductor-stop.sh + subagent-stop.sh transcript-reading ownership gates (class 1 closure; all-emitters foreign-drive)
