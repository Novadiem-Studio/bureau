name: coderabbit-gate distinguishes a real review from the two states where the bot comments WITHOUT reviewing (draft-skip, rate-limit)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  G="$ROOT/scripts/coderabbit-gate.sh"
  HEAD=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  BASE=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  run() { bash "$G" --comments-file "$1" --head "$HEAD" --inline-count "$2" ${3:+--log "$3"} 2>&1; }

  # A — a REAL review of the current head, nothing actionable. The only passing state.
  printf 'Reviewing files that changed from the base of the PR and between %s and %s.\n' "$BASE" "$HEAD" > "$TMPF/ok.txt"
  out=$(run "$TMPF/ok.txt" 0); rc=$?
  [ $rc -eq 0 ] || { echo "FAIL: A should pass, rc=$rc: $out"; rm -rf "$TMPF"; exit 1; }

  # B — draft skip. The bot DID comment; it did NOT review. This is the Bureau's
  # default outcome, since pr-delivery.sh open always passes --draft.
  printf '<!-- This is an auto-generated comment: skip review by coderabbit.ai -->\nDraft PRs are not automatically reviewed by default.\n' > "$TMPF/draft.txt"
  out=$(run "$TMPF/draft.txt" 0); rc=$?
  [ $rc -eq 1 ] || { echo "FAIL: B (draft skip) must fail, rc=$rc"; rm -rf "$TMPF"; exit 1; }
  printf '%s' "$out" | grep -q 'SKIPPED' || { echo "FAIL: B should name the skip: $out"; rm -rf "$TMPF"; exit 1; }
  printf '%s' "$out" | grep -q 'Draft PRs are not automatically reviewed' || { echo "FAIL: B should quote the draft reason: $out"; rm -rf "$TMPF"; exit 1; }

  # B2 — the SAME skip marker, a DIFFERENT cause: repo under the free tier's
  # star threshold. The marker is overloaded, so the gate must quote CodeRabbit's
  # own reason rather than assert one. An earlier version said "draft PR" here
  # and was wrong on a non-draft PR (bureau #35, 2026-09-13).
  printf '<!-- This is an auto-generated comment: skip review by coderabbit.ai -->\nThis repository does not receive automatic reviews because it has fewer than 10 stars.\n' > "$TMPF/stars.txt"
  out=$(run "$TMPF/stars.txt" 0); rc=$?
  [ $rc -eq 1 ] || { echo "FAIL: B2 (star threshold) must fail, rc=$rc"; rm -rf "$TMPF"; exit 1; }
  printf '%s' "$out" | grep -q 'fewer than 10 stars' \
    || { echo "FAIL: B2 must quote the real reason, got: $out"; rm -rf "$TMPF"; exit 1; }
  printf '%s' "$out" | grep -q 'draft' \
    && { echo "FAIL: B2 must NOT claim draft; marker is overloaded: $out"; rm -rf "$TMPF"; exit 1; }

  # C — rate limit / exhausted credits. Also comments, also did not review.
  printf '<!-- This is an auto-generated comment: rate limited by coderabbit.ai -->\nReview limit reached\n' > "$TMPF/rl.txt"
  out=$(run "$TMPF/rl.txt" 0); rc=$?
  [ $rc -eq 1 ] || { echo "FAIL: C (rate limit) must fail, rc=$rc"; rm -rf "$TMPF"; exit 1; }
  printf '%s' "$out" | grep -q 'RATE LIMITED' || { echo "FAIL: C should name the rate limit: $out"; rm -rf "$TMPF"; exit 1; }

  # D — STALE: a real review, but of an earlier commit. The merged tree was never seen.
  printf 'Reviewing files that changed from the base of the PR and between %s and %s.\n' "$BASE" cccccccccccccccccccccccccccccccccccccccc > "$TMPF/stale.txt"
  out=$(run "$TMPF/stale.txt" 0); rc=$?
  [ $rc -eq 1 ] || { echo "FAIL: D (stale) must fail, rc=$rc"; rm -rf "$TMPF"; exit 1; }
  printf '%s' "$out" | grep -q 'STALE' || { echo "FAIL: D should name staleness: $out"; rm -rf "$TMPF"; exit 1; }

  # E — no comment at all (bot absent). Silence is not approval.
  : > "$TMPF/none.txt"
  out=$(run "$TMPF/none.txt" 0); rc=$?
  [ $rc -eq 1 ] || { echo "FAIL: E (no comment) must fail, rc=$rc"; rm -rf "$TMPF"; exit 1; }

  # F — reviewed current head, but findings present and NOT dispositioned.
  out=$(run "$TMPF/ok.txt" 3); rc=$?
  [ $rc -eq 1 ] || { echo "FAIL: F (undispositioned findings) must fail, rc=$rc"; rm -rf "$TMPF"; exit 1; }

  # G — same findings, dispositioned in log.md for THIS head -> passes.
  printf 'CODERABBIT-EVENT: {"head":"%s","findings":3,"disposition":"addressed","note":"all three fixed"}\n' "$HEAD" > "$TMPF/log.md"
  out=$(run "$TMPF/ok.txt" 3 "$TMPF/log.md"); rc=$?
  [ $rc -eq 0 ] || { echo "FAIL: G (dispositioned) should pass, rc=$rc: $out"; rm -rf "$TMPF"; exit 1; }

  # H — a disposition for a DIFFERENT head must not clear findings on this one.
  printf 'CODERABBIT-EVENT: {"head":"%s","findings":3,"disposition":"addressed"}\n' dddddddddddddddddddddddddddddddddddddddd > "$TMPF/log2.md"
  out=$(run "$TMPF/ok.txt" 3 "$TMPF/log2.md"); rc=$?
  [ $rc -eq 1 ] || { echo "FAIL: H (wrong-head disposition) must fail, rc=$rc"; rm -rf "$TMPF"; exit 1; }

  # I — the seam is all-or-nothing, so it cannot half-engage in production.
  bash "$G" --comments-file "$TMPF/ok.txt" --head "$HEAD" >/dev/null 2>&1
  [ $? -eq 2 ] || { echo "FAIL: I partial seam should exit 2"; rm -rf "$TMPF"; exit 1; }

  rm -rf "$TMPF"
  echo PASS
expected: exit 0; stdout "PASS". Only a review whose reported commit range ends at the current head passes. Draft-skip and rate-limit comments fail even though the bot commented (the trap this gate exists for: presence of a comment is not evidence of a review). A stale range, an absent bot, and undispositioned findings all fail; a CODERABBIT-EVENT disposition keyed to the current head clears findings, one keyed to another head does not. Mutation: delete the `skip review by coderabbit.ai` branch in scripts/coderabbit-gate.sh → case B passes and its assertion fails.
phase: eval follow-up — CodeRabbit reliability
owner: scripts/coderabbit-gate.sh; docs/github-delivery.md; issue #32
