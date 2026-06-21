name: FR-44 guard present in delegate.md; no preference-modeling logic in bundle scripts/config
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  # Step 1 (positive): delegate.md must carry the FR-44 boundary-guard sentence.
  if grep -q 'does not model or predict' "$ROOT/agents/delegate.md"; then
    echo "guard:present"
  else
    echo "guard:MISSING"
  fi
  # Step 2 (negative): the scripts and config must contain NO preference-modeling
  # logic. The patterns target code/logic that models Robin's preferences; the
  # guard prose ("does not model or predict") lives in delegate.md, which is NOT
  # in this file set, so the legitimate guard text cannot trip the negative check.
  MODELING=$(grep -rliE \
    'predict.*decision|model.*preference|robin.*would|what.*robin.*wants|taste.*pattern|calibrated.*prediction' \
    "$ROOT/scripts/watcher.sh" \
    "$ROOT/scripts/verdict-write.sh" \
    "$ROOT/scripts/delegate-launcher.sh" \
    "$ROOT/config/delegate-verdict.schema.json" \
    "$ROOT/config/model-policy.v2.json" 2>/dev/null | wc -l | tr -d ' ')
  echo "modeling:$MODELING"
expected: prints "guard:present" and "modeling:0" — the FR-44 guard sentence is in delegate.md and zero bundle scripts/config files contain preference-modeling logic (AC 17 / FR 44)
phase: 12 · principal-delegate
owner: agents/delegate.md, all bundle scripts
