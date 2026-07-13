name: byte-identity-guard-clean-corpus-fixtures-171-178-unchanged-after-fr5-fr6 (AC-11/15)
phase: 01+04 · enforcement-relocation (FR 10 byte-identity gate)
owner: scripts/account-tokens.sh + scripts/account-run.sh — clean input unchanged after normalize_event parameterization
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  DIR="$ROOT/.bureau/regression"

  # Run each baseline fixture (171-178) individually and assert each exits 0.
  # Any failure indicates that FR 5/FR 6 changes perturbed a clean corpus.
  failed=""
  for n in 171 172 173 174 175 176 177 178; do
    f=$(ls "$DIR/${n}-"*.md 2>/dev/null | head -1)
    [ -n "$f" ] || { echo "FAIL: fixture $n not found"; exit 1; }
    # Skip retired/slow fixtures (shouldn't be any in 171-178, but guard anyway)
    if grep -q '^retired:' "$f" || grep -q '^slow:' "$f"; then
      continue
    fi
    cmd=$(awk '
      /^command:[[:space:]]*\|[[:space:]]*$/ { blk = 1; next }
      blk == 1 {
        if ($0 ~ /^[[:space:]]/ || $0 == "") { sub(/^  /, ""); print; next }
        blk = 0
      }
    ' "$f")
    [ -n "$cmd" ] || { echo "FAIL: fixture $n has no command block"; exit 1; }
    out=$(sh -c "$cmd" 2>&1); rc=$?
    if [ "$rc" -ne 0 ]; then
      failed="$failed $n"
      echo "  baseline $n FAILED: $(printf '%s\n' "$out" | tail -1)"
    fi
  done

  if [ -n "$failed" ]; then
    echo "FAIL: baseline fixtures NOT passing after FR5/FR6 changes:$failed"
    exit 1
  fi

  echo "PASS"
  # Mutation note: in a scratch copy of account-tokens.sh, revert normalize_event back
  # to def normalize_event: (no $required) and remove the isolation branches for
  # required-field absent/empty ids. If the refactor accidentally changes output for
  # clean input, the downstream fixtures (171-178) will fail and this fixture catches it.
  # Each baseline fixture verifies byte-identity on a clean corpus; failure here means
  # the FR5/FR6 parameterization broke clean-input behavior.
