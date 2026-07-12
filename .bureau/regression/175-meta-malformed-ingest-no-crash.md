name: class-closure Guard 4 (malformed-ingest doesn't crash) — a corpus with FOUR poison SPAWN-TOKEN-EVENTs (string numeric field, object attempt_id, object agent_id, scalar tokens) PLUS a started SPAWN-EVENT with an object attempt_id (the exact F3 reduce path into spawn_tokens_map) plus clean survivors, driven end-to-end through account-run.sh, exits 0 at schema_version 2 (NOT the schema-1 drop): the poison fields are coerced/isolated to synthetic keys instead of aborting the jq pass, the clean survivors' metrics survive, the malformed started-spawn does NOT leak into a real spawn_tokens map entry, and each malformed record is surfaced in a _notes breadcrumb
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d); trap 'rm -rf "$TMPF"' EXIT

  # ── CLASS FRAMING (read before adding a value read as a number or an object key) ─
  # This is the CLASS guard for malformed-ingest class ("a poison field aborts the
  # whole account-tokens.sh jq pass and drops the run to schema_version 1"). The
  # confirmed F2 reproduction, inverted into a guard: before ingest normalization a
  # string-valued numeric field ("string and number cannot be added") or a non-string
  # attempt_id/agent_id used as an object key ("Cannot use object as object key")
  # threw inside the single jq pass at account-tokens.sh's assembly; account-run.sh
  # caught the non-zero exit and dropped to schema_version 1, losing ALL token
  # metrics. account-tokens.sh's ingest normalize_event now COERCES every numeric
  # field (numbers // 0) and type-gates every id (non-string → null), so each poison
  # field isolates to a safe value and the pass completes.
  #
  # IF YOU ADD A NEW value read as a numeric or an object key in account-tokens.sh,
  # add a poison row here so the "a malformed field must isolate, not abort" property
  # is proven for it too.

  # A valid YYYYMMDD-slug run dir basename + a valid state.json (account-run.sh
  # calendar-validates the basename and hard-fails on a missing state.json).
  RP="$TMPF/20260712-malformed-ingest-no-crash"; mkdir -p "$RP"
  printf '%s\n' '{"workflow":"feature","phase_status":"complete","phases_complete":[],"critic_loops":{"mage":1}}' > "$RP/state.json"

  # Corpus: FOUR poison records (each in a dangerous position) + clean survivors.
  #  (1) string numeric:    tokens.input is "oops"     (the jq add-crash vector)
  #  (2) object attempt_id: attempt_id is {...}        (group_by/reduce object-key crash)
  #  (3) object agent_id:   agent_id is {...}          (group_by/reduce object-key crash)
  #  (4) scalar tokens:     tokens is 96666            (already-covered, kept for regression)
  #  + one CLEAN specialist spawn (200) + one CLEAN conductor line (100) = the survivors.
  # Poison records carry zero components so they contribute 0 to the totals; the point
  # is that they ISOLATE (not crash), and the clean survivors' metrics are correct.
  printf '%s\n' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"started","at":"2026-07-12T00:00:00Z","rework":false}' \
    'SPAWN-EVENT: {"role":"mage","agent":"The Mage","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":"mage-1","status":"complete","at":"2026-07-12T00:01:00Z","started_at":"2026-07-12T00:00:00Z"}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"mage-1","agent_id":"agent-clean","at":"2026-07-12T00:01:00Z","turns":2,"tokens":{"input":100,"cache_creation":50,"cache_read":50,"processed":200,"output":5}}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"poison-str","agent_id":"agent-p1","at":"2026-07-12T00:01:30Z","turns":1,"tokens":{"input":"oops","cache_creation":0,"cache_read":0,"processed":0,"output":0}}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":{"bad":"obj"},"agent_id":"agent-p2","at":"2026-07-12T00:01:40Z","turns":1,"tokens":{"input":0,"cache_creation":0,"cache_read":0,"processed":0,"output":0}}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"poison-aid","agent_id":{"bad":"obj"},"at":"2026-07-12T00:01:50Z","turns":1,"tokens":{"input":0,"cache_creation":0,"cache_read":0,"processed":0,"output":0}}' \
    'SPAWN-TOKEN-EVENT: {"attempt_id":"poison-scalar","agent_id":"agent-p4","at":"2026-07-12T00:02:00Z","turns":1,"tokens":96666}' \
    'SPAWN-EVENT: {"role":"smith","agent":"The Systemsmith","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":{"bad":"started-obj"},"status":"started","at":"2026-07-12T00:02:10Z","rework":false}' \
    'SPAWN-EVENT: {"role":"smith","agent":"The Systemsmith","configured_model":"sonnet","actual_model":"sonnet","attempt":1,"attempt_id":{"bad":"started-obj"},"status":"complete","at":"2026-07-12T00:02:20Z","started_at":"2026-07-12T00:02:10Z"}' \
    'CONDUCTOR-TOKEN-EVENT: {"session_id":"c1","at":"2026-07-12T00:03:00Z","turns":5,"tokens":{"input":40,"cache_creation":30,"cache_read":30,"processed":100,"output":2},"final":true}' \
    > "$RP/log.md"

  bash "$ROOT/scripts/account-run.sh" "$RP" >/dev/null 2>&1
  rc=$?
  [ "$rc" = "0" ] || { echo "FAIL: account-run.sh exited $rc on the poison corpus (must be 0)"; exit 1; }
  ACC="$RP/accounting.json"
  [ -f "$ACC" ] || { echo "FAIL: no accounting.json written"; exit 1; }

  # ── Assertion 1: schema_version 2 (NOT the schema-1 drop — the whole point of F2) ─
  jq -e '.schema_version == 2' "$ACC" > /dev/null \
    || { echo "FAIL: a poison field aborted the pass and account-run dropped to schema_version $(jq -r .schema_version "$ACC") (expected 2)"; exit 1; }

  # ── Assertion 2: the clean survivors' metrics survive and are CORRECT ──────────
  # processed_total = clean spec 200 + conductor 100 = 300 (poison records → 0).
  # The clean specialist spawn's derived processed (200) survives in specialist_spawns.
  # The conductor block is exact with its 100.
  jq -e '
    .tokens.processed_total.value == 300 and
    .conductor_tokens.tokens.processed == 100 and
    .conductor_tokens.confidence == "exact" and
    (.specialist_spawns[0].tokens.processed.value == 200)
  ' "$ACC" > /dev/null \
    || { echo "FAIL: a clean survivor metric was lost/wrong: $(jq -c '{pt:.tokens.processed_total.value,cond:.conductor_tokens.tokens.processed,sp:.specialist_spawns[0].tokens.processed.value}' "$ACC")"; exit 1; }

  # ── Assertion 3: each malformed record is SURFACED, not silently swallowed ─────
  # The normalization advisory names the malformed events (>= 4: the four poison
  # SPAWN-TOKEN-EVENTs + the object-attempt_id started/terminal SPAWN-EVENTs); the
  # object-id poison records land in unattributed_records (isolated to a synthetic key
  # and routed there) so a reader can see exactly which were isolated.
  jq -e '(._notes // []) | join(" ")
         | test("token event\\(s\\) had a malformed field")' "$ACC" > /dev/null \
    || { echo "FAIL: the malformed-field advisory did not surface: $(jq -c '._notes' "$ACC")"; exit 1; }
  jq -e '(.tokens.unattributed_records | length) >= 1 and
         ([.tokens.unattributed_records[] | select(._norm_note != null)] | length) >= 1' "$ACC" > /dev/null \
    || { echo "FAIL: no isolated poison record surfaced in unattributed_records with a _norm_note: $(jq -c '.tokens.unattributed_records' "$ACC")"; exit 1; }

  # ── Assertion 4 (F3 — the exact reduce path): a STARTED SPAWN-EVENT with an object ─
  # attempt_id survives group_by(.attempt_id) | map(.[0]) into $pairs and reaches the
  # spawn_tokens_map reduce (account-tokens.sh:635). Pre-fix its attempt_id coerced to
  # null → `Cannot use null as object key` crashed the pass → account-run dropped to
  # schema 1 (Assertion 1 above already pins schema 2). Here we ALSO pin that the
  # malformed started-spawn was NOT published as a real spawn_tokens map entry: no
  # accounting.json spawn (specialist_spawns / spawn_tokens) may carry a synthetic
  # __malformed__ attempt_id — it was filtered out of the reduce (§1.3) and only
  # surfaced via unattributed / the norm advisory.
  jq -e '
    ([ (.specialist_spawns // [])[]?, (.spawn_tokens // {} | to_entries[]?.value) ]
     | map(select((.attempt_id // "" | tostring) | test("__malformed__")))
     | length) == 0
  ' "$ACC" > /dev/null \
    || { echo "FAIL: a synthetic-key (malformed) started-spawn leaked into a real spawn_tokens map entry: $(jq -c '.spawn_tokens' "$ACC")"; exit 1; }

  echo "PASS"
  # Mutation note (the confirmed F2/F3 reproduction, inverted). The fix is belt-and-
  # suspenders at the reduce, so reproducing the F3 crash needs BOTH guards reverted:
  #  (a) the isolate primitive — map a non-string attempt_id back to null instead of a
  #      synthetic key, AND
  #  (b) the §1.3 defensive `select(.attempt_id != null …)` filter on the reduce input.
  # With both reverted, the object-attempt_id STARTED SPAWN-EVENT coerces to null and
  # reaches the spawn_tokens_map reduce as a null object key ("Cannot use null as object
  # key") — the exact F3 crash → account-tokens exits non-zero → account-run drops to
  # schema_version 1 → the `schema_version == 2` assertion fails. (Reverting (a) alone
  # leaves (b) to skip the null-key record — no crash — which is the belt-and-suspenders
  # design working, not a gap. The string-numeric field crash is reproduced by dropping
  # `| numbers // 0` in coerce_tokens.) Restore → passes.
expected: exit 0; stdout "PASS"; a corpus with four poison SPAWN-TOKEN-EVENTs (string-numeric field, object attempt_id, object agent_id, scalar tokens) PLUS a started SPAWN-EVENT with an object attempt_id (the F3 reduce path) plus clean survivors drives account-run.sh to exit 0 at schema_version 2 (not the schema-1 drop); the clean survivors' metrics are correct (processed_total 300 = spec 200 + conductor 100, specialist spawn 200, conductor exact); the malformed records are surfaced in a _notes advisory and land in unattributed_records with a _norm_note; the malformed started-spawn does NOT leak into a real spawn_tokens map entry. Mutation-test: reverting the isolate primitive crashes the pass (string-add or null-object-key at the reduce) and drops the run to schema_version 1.
phase: 04 · feature — class-closure Guard 4 (malformed-ingest-doesn't-crash meta-fixture)
owner: account-tokens.sh ingest normalize_event coercion/type-gating (class 4 closure; malformed-field isolation)
