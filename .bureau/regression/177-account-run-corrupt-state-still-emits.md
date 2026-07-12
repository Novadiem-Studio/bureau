name: account-run — a corrupt (unparseable OR valid-non-object) state.json degrades and STILL emits accounting.json at schema_version 1 with a top-level _state_note and all state-derived fields unavailable (F4/B6), while a WHOLLY ABSENT state.json still hard-fails (exit 1, no artifact) — the degrade does not swallow the genuine "not a run dir" error
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); trap 'rm -rf "$TMPF"' EXIT
  fail() { echo "FAIL: $*"; exit 1; }

  # ── FRAMING ───────────────────────────────────────────────────────────────────
  # F4 reproduction, inverted: account-run.sh:589 read $STATE_JSON with an UNGUARDED
  # jq (`memory_type=$(jq -r … "$STATE_JSON")`). Under `set -euo pipefail` a corrupt /
  # non-object state.json made that jq exit non-zero, aborting the whole script (exit
  # 5) BEFORE tmp_out was created — no accounting.json at all, exactly when a downstream
  # observer most needs a terminal artifact saying "state.json was corrupt". The fix
  # validates state.json ONCE early (STATE_CORRUPT), guards the memory read, and adds a
  # top-level _state_note; the run degrades to schema_version 1 and STILL emits.
  #
  # The ONE hard-fail preserved (Corpus C): a WHOLLY ABSENT state.json still dies —
  # that is "not a framework run dir" (a caller error), not an abnormal run. Corpus C
  # is the regression pin that §4's degrade did NOT weaken the absent-hardfail (fixture
  # 112 covers absent-hardfail on its own; C proves the degrade left it intact).

  assert_corrupt_emits() {
    RP="$1"; label="$2"
    bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1
    rc=$?
    [ "$rc" = "0" ] || fail "$label: account-run exited $rc (expect 0 — corrupt state.json must degrade, not abort)"
    ACC="$RP/accounting.json"
    [ -f "$ACC" ] || fail "$label: no accounting.json written (the F4 abort)"
    jq -e '.schema_version == 1' "$ACC" >/dev/null \
      || fail "$label: schema_version $(jq -r .schema_version "$ACC") (expect 1 on a corrupt state.json)"
    # top-level _state_note names the corrupt state.json.
    jq -e '(._state_note // "") | test("state.json"; "i") and test("parseable JSON object")' "$ACC" >/dev/null \
      || fail "$label: missing/wrong top-level _state_note: $(jq -c '._state_note // "(absent)"' "$ACC")"
    # every state-derived field is unavailable (.run.workflow, .phases.status/critic_loops).
    jq -e '.run.workflow.confidence == "unavailable"
           and .phases.status.confidence == "unavailable"
           and .phases.critic_loops.confidence == "unavailable"' "$ACC" >/dev/null \
      || fail "$label: a state-derived field is not unavailable: $(jq -c '{w:.run.workflow.confidence,p:.phases.status.confidence,c:.phases.critic_loops.confidence}' "$ACC")"
    # memory block all-unavailable with the corrupt note.
    jq -e '(.memory.retrieval_count.confidence == "unavailable")
           and ((.memory._note // "") | test("not a parseable JSON object"))' "$ACC" >/dev/null \
      || fail "$label: memory block not all-unavailable-with-corrupt-note: $(jq -c '.memory' "$ACC")"
  }

  # ── Corpus A (unparseable garbage) ─────────────────────────────────────────────
  RPA="$TMPF/20260712-corrupt-a"; mkdir -p "$RPA"
  printf '%s' 'not json {{{' > "$RPA/state.json"
  printf 'run log\n' > "$RPA/log.md"
  assert_corrupt_emits "$RPA" "A(unparseable)"

  # ── Corpus B (valid JSON but NON-object: an array) ─────────────────────────────
  RPB="$TMPF/20260712-corrupt-b"; mkdir -p "$RPB"
  printf '%s' '[1,2,3]' > "$RPB/state.json"
  printf 'run log\n' > "$RPB/log.md"
  assert_corrupt_emits "$RPB" "B(non-object-array)"

  # ── Corpus C (WHOLLY ABSENT — the ONE hard-fail preserved) ─────────────────────
  RPC="$TMPF/20260712-corrupt-c"; mkdir -p "$RPC"
  printf 'run log\n' > "$RPC/log.md"   # deliberately no state.json
  outc=$(bash "$ROOT/scripts/account-run.sh" "$RPC" 2>&1) && fail "C(absent): account-run exited 0 (expect hard-fail non-zero on a wholly-absent state.json)"
  printf '%s' "$outc" | grep -q 'state.json' || fail "C(absent): hard-fail message does not mention state.json"
  [ ! -f "$RPC/accounting.json" ] || fail "C(absent): an accounting.json was written on the absent-hardfail path (the degrade swallowed the genuine 'not a run dir' error)"

  echo "PASS"
  # Mutation note (the confirmed F4 reproduction, inverted): in a scratch copy of
  # scripts/account-run.sh, remove the STATE_CORRUPT validate-once + the guarded memory
  # read (restore the raw unguarded `memory_type=$(jq -r … "$STATE_JSON")` at ~589).
  # Then Corpus A/B abort at exit 5 with NO accounting.json → assert_corrupt_emits's
  # exit-0 / file-exists checks fail. Restore → passes. Corpus C is unaffected by the
  # mutation (it never reaches the memory read); it pins that the degrade never weakened
  # the absent-hardfail.
expected: exit 0; stdout "PASS"; a corrupt state.json (Corpus A unparseable garbage, Corpus B a valid-JSON array) drives account-run to exit 0 with accounting.json at schema_version 1, all state-derived fields unavailable, memory block all-unavailable, and a top-level _state_note naming the corrupt state.json; a wholly-absent state.json (Corpus C) still hard-fails (non-zero, no accounting.json, message mentions state.json). Mutation-test: restoring the raw unguarded line-589 jq aborts Corpus A/B at exit 5 with no artifact.
phase: 04 · feature — F4 always-emit-on-corrupt-state guard
owner: account-run.sh STATE_CORRUPT validate-once + guarded memory read + _state_note (F4/B6 controlled-degrade)
