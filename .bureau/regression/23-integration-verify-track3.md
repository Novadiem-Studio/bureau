name: Track-3 integration-verify replay — proceed + mislabeled-regression + absent-evidence
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT INT TERM

  # ── Controlled fixture git repo: a base commit + a branch commit. ──
  # The base-ref / branch-tip are these fixture-local SHAs — NEVER the literal
  # string "main" (W1). The commit graph is deterministic, so the replay result
  # is deterministic. This repo stands in for the worktree under review.
  REPO="$TMPDIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email t@t.t
  git -C "$REPO" config user.name fixture
  printf 'base\n' > "$REPO/file.txt"
  git -C "$REPO" add file.txt
  git -C "$REPO" commit -q -m base
  BASE_SHA=$(git -C "$REPO" rev-parse HEAD)
  printf 'branch\n' >> "$REPO/file.txt"
  git -C "$REPO" add file.txt
  git -C "$REPO" commit -q -m branch
  BRANCH_SHA=$(git -C "$REPO" rev-parse HEAD)

  # ── The artifact under review; its SHA-256 is what request + verdict must agree on. ──
  ART="$TMPDIR/artifact.md"
  printf 'integration merge artifact\n' > "$ART"
  HASH=$(sha256sum "$ART" 2>/dev/null | awk '{print $1}')
  [ -n "$HASH" ] || HASH=$(shasum -a 256 "$ART" | awk '{print $1}')

  # ── A request file carrying ALL fields verdict-write.sh requires (lines 199-225),
  # plus checkpoint-type: integration which arms the step-2b integration guard. ──
  write_request() {
    {
      echo "artifact-hash: $HASH"
      echo "revise-count: 0"
      echo "checkpoint: 01"
      echo "attempt: 1"
      echo "checkpoint-type: integration"
      echo "artifact: $ART"
    } > "$1"
  }

  ok=0

  # ── (a) HAPPY-PATH PROCEED (AC-14, AC-10) ──
  # 4 green canonical gates + 1 claimed-pre-existing red (AC-PRIVATE) CONFIRMED
  # pre-existing at the fixture base; Under-declaration empty; Scope-diff-clean true;
  # Fast-forward-ok true. Expect: exit 0, verdict written, decision: proceed.
  write_request "$TMPDIR/a-request.md"
  cat > "$TMPDIR/a.out.json" <<JSON
  {"Decision":"proceed","Artifact-hash":"$HASH","Uncertainties":"none","Rationale":"all canonical gates green at $BRANCH_SHA; AC-PRIVATE confirmed pre-existing at base $BASE_SHA","Required-changes":"none","Escalation":"none","Ledger":"01.1","Integration-evidence":{"Gates-checked":[{"name":"regression","result":"green"},{"name":"npm-build","result":"green"},{"name":"npm-typecheck","result":"green"},{"name":"npm-test","result":"green"}],"Pre-existing-validated":[{"name":"AC-PRIVATE","confirmed-pre-existing":true,"exit-code-base":1,"exit-code-branch":1}],"Under-declaration":[],"Scope-diff-clean":true,"Scope-violations":[],"Fast-forward-ok":true,"Conflicts-clean":true}}
  JSON
  "$ROOT/scripts/verdict-write.sh" "$TMPDIR/a.out.json" "$TMPDIR/a-request.md" "$TMPDIR/a-verdict.md" "$TMPDIR/a-ledger.md" "$TMPDIR" 2 >/dev/null 2>&1
  if [ "$?" -eq 0 ] && [ -f "$TMPDIR/a-verdict.md" ] && grep -q '^decision:[[:space:]]*proceed' "$TMPDIR/a-verdict.md"; then
    ok=$((ok + 1)); echo "case-a:proceed-ok"
  else
    echo "case-a:FAIL"
  fi

  # ── (b) MISLABELED-REGRESSION REJECTION (EC-B14-2, AC-4) ──
  # A proceed verdict whose Pre-existing-validated entry carries
  # confirmed-pre-existing: false (passes at base, fails on branch = a real
  # regression dressed up as pre-existing). Expect: exit 2, NO verdict file.
  write_request "$TMPDIR/b-request.md"
  cat > "$TMPDIR/b.out.json" <<JSON
  {"Decision":"proceed","Artifact-hash":"$HASH","Uncertainties":"none","Rationale":"claimed pre-existing but it is a fresh regression","Required-changes":"none","Escalation":"none","Ledger":"01.1","Integration-evidence":{"Gates-checked":[{"name":"regression","result":"green"}],"Pre-existing-validated":[{"name":"AC-PRIVATE","confirmed-pre-existing":false,"exit-code-base":0,"exit-code-branch":1}],"Under-declaration":[],"Scope-diff-clean":true,"Scope-violations":[],"Fast-forward-ok":true,"Conflicts-clean":true}}
  JSON
  "$ROOT/scripts/verdict-write.sh" "$TMPDIR/b.out.json" "$TMPDIR/b-request.md" "$TMPDIR/b-verdict.md" "$TMPDIR/b-ledger.md" "$TMPDIR" 2 >/dev/null 2>&1
  if [ "$?" -eq 2 ] && [ ! -f "$TMPDIR/b-verdict.md" ]; then
    ok=$((ok + 1)); echo "case-b:rejected-ok"
  else
    echo "case-b:FAIL"
  fi

  # ── (c) ABSENT-INTEGRATION-EVIDENCE REJECTION (EC-B14-11, AC-8) ──
  # An integration checkpoint verdict missing the Integration-evidence key entirely.
  # The presence guard must reject it. Expect: exit 2, NO verdict file.
  write_request "$TMPDIR/c-request.md"
  cat > "$TMPDIR/c.out.json" <<JSON
  {"Decision":"proceed","Artifact-hash":"$HASH","Uncertainties":"none","Rationale":"integration checkpoint but Integration-evidence omitted","Required-changes":"none","Escalation":"none","Ledger":"01.1"}
  JSON
  "$ROOT/scripts/verdict-write.sh" "$TMPDIR/c.out.json" "$TMPDIR/c-request.md" "$TMPDIR/c-verdict.md" "$TMPDIR/c-ledger.md" "$TMPDIR" 2 >/dev/null 2>&1
  if [ "$?" -eq 2 ] && [ ! -f "$TMPDIR/c-verdict.md" ]; then
    ok=$((ok + 1)); echo "case-c:rejected-ok"
  else
    echo "case-c:FAIL"
  fi

  [ "$ok" -eq 3 ] && echo "FIXTURE-23-PASS"
  test "$ok" -eq 3
expected: prints "case-a:proceed-ok", "case-b:rejected-ok", "case-c:rejected-ok", "FIXTURE-23-PASS" and exits 0. All three sub-cases must hold: (a) a well-formed integration proceed verdict (4 green canonical gates + AC-PRIVATE confirmed pre-existing at the fixture-local base SHA) is accepted by verdict-write.sh (exit 0, verdict file present, decision: proceed); (b) a proceed verdict with a Pre-existing-validated entry carrying confirmed-pre-existing:false is rejected (exit 2, no verdict file) — the mislabeled-regression guard; (c) an integration checkpoint verdict missing Integration-evidence is rejected (exit 2, no verdict file) — the presence guard. Hermetic: a controlled git repo (base + branch commit) supplies fixture-local SHAs as base-ref/branch-tip — never the literal "main"; the tmpdir is removed on exit. Mutation-test: deleting the step-2b integration guard from verdict-write.sh makes (b) and (c) wrongly proceed (exit 0, verdict written), so the fixture exits non-zero.
phase: 14 · delegate-verifying-mode
owner: scripts/watcher.sh scripts/verdict-write.sh agents/delegate.md
