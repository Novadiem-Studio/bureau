name: byte-identity-guard-clean-corpus-fixtures-171-187-unchanged-after-verdict-binding (AC-15/FR-11)
phase: 04 · verdict-binding (FR 11 byte-identity guard)
owner: scripts/verdict-gate.sh — clean corpus 171-187 unchanged after verdict binding
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  DIR="$ROOT/.bureau/regression"

  # Run each baseline fixture (171-187) individually and assert each exits 0.
  # Any failure indicates that verdict-binding changes perturbed a clean corpus.
  failed=""
  for n in 171 172 173 174 175 176 177 178 179 180 181 182 183 184 185 186 187; do
    f=$(ls "$DIR/${n}-"*.md 2>/dev/null | head -1)
    [ -n "$f" ] || { echo "FAIL: fixture $n not found"; exit 1; }
    # Skip retired/slow fixtures (shouldn't be any in 171-187, but guard anyway)
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
    echo "FAIL: baseline fixtures NOT passing after verdict-binding changes:$failed"
    exit 1
  fi

  echo "PASS"
  # Mutation note: in a scratch copy of verdict-gate.sh, introduce a change that alters one
  # of the account-tokens or emit-event fixtures. These share no code path with verdict-gate.sh
  # in practice; this guard proves no shared clean-corpus behavior was touched.
expected: PASS
