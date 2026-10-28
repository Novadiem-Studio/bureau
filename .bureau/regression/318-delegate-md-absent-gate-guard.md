name: F318 · delegate.md verifying checklist treats an absent gate as informational and escalates only when every gate is absent (issue #115)
phase: 115 · integration gate regression runner resolution
owner: agents/delegate.md — Five-step verifying checklist, Step 1 and Proceed rule
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  DM="$ROOT/agents/delegate.md"
  PATH=/usr/bin:$PATH
  grep -q 'For each entry with `result: "absent"`: no runner existed' "$DM" \
    || { echo "FAIL: Step 1 absent-gate rule missing"; exit 1; }
  grep -q 'Absent is not a' "$DM" && grep -q 'failure and not a hidden red gate' "$DM" \
    || { echo "FAIL: absent-is-not-failure wording missing"; exit 1; }
  grep -q 'no canonical gate ran: <names> absent' "$DM" \
    || { echo "FAIL: every-gate-absent escalation missing"; exit 1; }
  grep -q 'Green and `absent` entries are informational' "$DM" \
    || { echo "FAIL: under-declaration absent carve-out missing"; exit 1; }
  grep -q 'or have `result: "absent"`), and at' "$DM" \
    || { echo "FAIL: proceed rule 1 absent carve-out missing"; exit 1; }
  echo "PASS"
  # Mutation note: delete the Step 1 absent paragraph; the first grep fails.
expected: PASS
