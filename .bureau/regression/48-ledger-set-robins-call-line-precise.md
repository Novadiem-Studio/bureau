name: F09 · ledger-set-robins-call.sh fills the escalate record's blank Robin's call; revise records stay blank; only the target line changes
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  SC="$ROOT/scripts/ledger-set-robins-call.sh"
  LA="$ROOT/scripts/ledger-append.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  # ---- Case A: single-record escalation, line-precision (record 01 already filled, untouched) ----
  A="$TMP/single.md"
  printf '## 01.1 — 2026-06-25T10:00:00Z\ndecision:      escalate\nartifact:      /a/x\nartifact-hash: aaa\nuncertainties: u1\nrationale:     r1\nborderline:    no\nrefs:          none\nRobin'"'"'s call:  approved earlier\n\n## 02.1 — 2026-06-25T11:00:00Z\ndecision:      escalate\nartifact:      /a/y\nartifact-hash: bbb\nuncertainties: u2\nrationale:     r2\nborderline:    no\nrefs:          none\nRobin'"'"'s call:\n' > "$A"
  REC01_BEFORE=$(sed -n '1,9p' "$A")
  LEDGER_FILE="$A" sh "$SC" 02 "approved as-is"
  grep -Fq "Robin's call:  approved as-is" "$A"
  [ "$REC01_BEFORE" = "$(sed -n '1,9p' "$A")" ]
  # ---- Case B: revise->escalate multi-record, built with the REAL ledger-append.sh ----
  B="$TMP/multi.md"
  sh "$LA" "$B" 05.1 revise   /a/p hashp uncP ratP no none
  sh "$LA" "$B" 05.2 escalate /a/q hashq uncQ ratQ no none
  [ "$(grep -Fxc "Robin's call:" "$B")" -eq 2 ]
  LEDGER_FILE="$B" sh "$SC" 05 "approved"
  grep -E -A8 '^## 05\.2 ' "$B" | grep -Fq "Robin's call:  approved"
  grep -E -A8 '^## 05\.1 ' "$B" | grep -Fxq "Robin's call:"
  [ "$(grep -Fxc "Robin's call:" "$B")" -eq 1 ]
expected: exit 0 — Case A: record 02's blank "Robin's call:" line is filled with "approved as-is" and record 01 (lines 1-9, already filled) is byte-identical. Case B (revise→escalate built with the real ledger-append.sh): ledger-set 05 fills the decision:escalate record (05.2) with "approved" and leaves the decision:revise record (05.1) blank — exactly one blank "Robin's call:" line remains. Nonzero if the script reverts to NN-ordinal-only matching (two blanks for 05 → it refuses or fills the wrong/revise record), or fills the wrong record.
phase: 03 · execute-plan (Delegate v2)
owner: prompts.md Prompt 3 (scripts/ledger-set-robins-call.sh)
