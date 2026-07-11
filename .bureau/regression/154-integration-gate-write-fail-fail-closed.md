name: F04 (Finding 2) · integration-gate.sh fails CLOSED when the evidence write fails — an unwritable --out dir yields exit 2 (a distinct fail code) with NO integration-results.json, never a false SUCCESS (exit 0) reporting no evidence
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
  # An --out dir that EXISTS (so the caller-owns-$CTX guard passes) but is NOT
  # writable, so the Python heredoc that writes integration-results.json raises
  # PermissionError. Skip on the (rare) case the harness runs as root, where a
  # 555 dir is still writable and the reproduction does not hold.
  OUT="$TMP/ctx"; mkdir -p "$OUT"
  printf '{"scope":{}}\n' > "$TMP/state.json"
  chmod 555 "$OUT"
  if [ -w "$OUT" ]; then echo "PASS (skip: --out still writable, likely root)"; exit 0; fi

  # ESCALATE branch (worktree=(none)) — the first heredoc write site. Under the
  # bug this branch's Python raised but the shell still hit `exit 0`: SUCCESS with
  # no evidence file. Under the fix it fails closed (exit 2).
  "$GATE" --checkpoint-type integration --worktree-path "(none)" --base-ref devel \
    --claimed-gates '[]' --state-json "$TMP/state.json" --out "$OUT" 2>/dev/null
  rc=$?
  chmod -R u+w "$TMP" 2>/dev/null

  # Load-bearing: the gate did NOT report a false SUCCESS. It exited 2 (the
  # distinct fail-closed code), NOT 0.
  [ "$rc" = "2" ] || { echo "FAIL: expected exit 2 (fail-closed), got $rc"; exit 1; }
  # And there is NO evidence file masquerading as valid output.
  [ ! -f "$OUT/integration-results.json" ] || { echo "FAIL: an evidence file exists despite the write failing"; exit 1; }
  echo "PASS"
  # Mutation note: the load-bearing guards are the `[ ! -w "$OUT" ]` preflight AND
  # the `assert_results_written` post-write assertion (the must). Remove BOTH (let
  # the write failure fall through to the trailing `exit 0`) and the gate exits 0
  # with no integration-results.json — a SUCCESS reporting no evidence — so the
  # `rc == 2` assertion fails. Removing only the preflight still fails closed via
  # the post-write assertion: the heredoc's PermissionError re-raises, the shell
  # (no set -e) falls through to assert_results_written, which sees an absent file
  # and exits 2. (Happy-path counter-guard: fixtures 40/41 assert a writable --out
  # still exits 0 WITH the file present, so the fix cannot over-fire.)
expected: exit 0; stdout "PASS"; an unwritable --out makes integration-gate.sh exit 2 (fail-closed, distinct code) with NO integration-results.json — never exit 0 (a false SUCCESS with no evidence). Skips cleanly when run as root (555 dir still writable).
phase: 03 · execute-plan (Delegate v2)
owner: scripts/integration-gate.sh fail-closed on write failure (Finding 2)
