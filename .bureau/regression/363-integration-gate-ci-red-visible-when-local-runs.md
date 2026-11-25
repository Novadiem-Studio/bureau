name: F363 · integration-gate.sh --gate-mode ci --final that runs the local suite still reads the head's CI once, as an extra veto that only a fully passed CI leaves green (issue #149)
phase: bug-fix (run 20261124-gate-edges-149, issue #149 item 5)
owner: scripts/integration-gate.sh (gate-mode resolution: final-gate CI veto)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  GATE="$ROOT/scripts/integration-gate.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT INT TERM
  W="$TMP/wt"; FK="$TMP/fake"; BIN="$TMP/bin"; GH_LOG="$TMP/gh.log"
  export W FK GH_LOG
  mkdir -p "$W/.bureau/regression" "$FK" "$BIN"
  git -C "$W" init -q -b main; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  # The local suite is green unless $FK/localred exists. No project-context.md: the bureau
  # repo's own case, so the final gate runs the full local suite.
  printf '#!/bin/sh\n[ -f "%s/localred" ] && exit 1\nexit 0\n' "$FK" > "$W/.bureau/regression/run.sh"
  git -C "$W" add -A; git -C "$W" commit -qm base
  BASE=$(git -C "$W" rev-parse HEAD)
  git -C "$W" checkout -q -b feat
  echo c1 > "$W/f.txt"; git -C "$W" add -A; git -C "$W" commit -qm c1
  SHA=$(git -C "$W" rev-parse HEAD)
  # Stub gh (first on PATH, ahead of any real /usr/bin/gh). $FK/mode picks the checks answer.
  cat > "$BIN/gh" <<'FAKEGH'
  #!/bin/sh
  printf '%s\n' "$*" >> "$GH_LOG"
  pwd -P >> "$FK/cwd.log"
  m=$(cat "$FK/mode" 2>/dev/null)
  # cwd mode: gh answers for the repository of the directory it runs in, as the real gh
  # does with no -R. Only the worktree's own repository has the red check.
  if [ "$m" = cwd ]; then
    if [ "$(pwd -P)" = "$(cd "$W" && pwd -P)" ]; then m=fail; else m=pass; fi
  fi
  case "$1 $2" in
    "pr view")
      # moved mode: the PR head changes after the checks are read (green on the old head).
      [ "$m" = moved ] && [ -f "$FK/read" ] && m=mismatch
      if [ "$m" = mismatch ]; then echo 0000000000000000000000000000000000000000; else git -C "$W" rev-parse HEAD; fi; exit 0 ;;
    "pr checks")
      [ "$m" = moved ] && { touch "$FK/read"; m=pass; }
      case "$m" in
        nochecks) echo "no checks reported on the 'feat' branch" >&2; exit 1 ;;
        error) echo "HTTP 502: Bad Gateway" >&2; exit 1 ;;
        big) cat "$FK/checks.json"; exit 0 ;;
        *) printf '[{"name":"tests","bucket":"%s","state":"X","workflow":"ci","link":""}]\n' "$m"; exit 0 ;;
      esac ;;
  esac
  exit 1
  FAKEGH
  chmod +x "$BIN/gh"
  printf '{"scope":{},"git":{"pr_number":7,"github_repo":"o/r"}}\n' > "$TMP/st.json"
  printf '{"scope":{},"git":{"pr_number":null}}\n' > "$TMP/st-nopr.json"
  printf '{"scope":{},"git":{"pr_number":7}}\n' > "$TMP/st-norepo.json"
  gate() {  # <case> <mode> <state> <extra args...>
    c="$1"; printf '%s' "$2" > "$FK/mode"; st="$3"; shift 3
    mkdir -p "$TMP/$c"; : > "$GH_LOG"
    PATH="$BIN:$PATH" "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
      --claimed-gates '[]' --state-json "$TMP/$st" --out "$TMP/$c" --ci-poll 1 --ci-timeout 3 "$@" 2>/dev/null
  }
  R() { printf '%s' "$TMP/$1/integration-results.json"; }
  # vetoed <case> <ci_status>: local suite ran green, the veto gate is red with that status.
  vetoed() {
    jq -e --arg s "$2" '.final_gate==true and .gate_mode=="local" and .ci==null
      and .gates[0].name=="regression" and .gates[0].result=="green"
      and ([.gates[] | select(.name=="ci-final-veto")] | length==1)
      and (.gates[-1] | .name=="ci-final-veto" and .result=="red" and .exit_code_branch!=0
           and .ci_status==$s and (.detail|length>0))
      and ([.under_declaration[].name] | index("ci-final-veto"))==null
      and (.gate_mode_reason|test("final gate CI veto: " + $s))' "$(R "$1")" >/dev/null \
      || { echo "FAIL $1"; jq -c '{gate_mode,gate_mode_reason,gates:[.gates[]|{name,result,ci_status,detail}]}' "$(R "$1")"; exit 1; }
  }

  # V1: CI red on the head -> the final gate carries a red veto naming the failed check, and pairing discards it.
  gate red fail st.json --gate-mode ci --final
  vetoed red failed
  jq -e '.gates[-1].failed==["tests"] and .gates[-1].head_sha==$s' --arg s "$SHA" "$(R red)" >/dev/null || { echo "FAIL red: failed check or head not recorded"; exit 1; }
  if "$ROOT/scripts/terminal-pairing.sh" --gate "$(R red)" --review-sha "$SHA" > "$TMP/pair.out" 2>&1; then echo "FAIL red: pairing accepted a CI-red final gate"; exit 1; fi
  grep -Fq 'ci-final-veto' "$TMP/pair.out" || { echo "FAIL red: pairing did not name the veto: $(cat "$TMP/pair.out")"; exit 1; }
  # V2: one read only, never a poll loop: one pr checks call.
  [ "$(grep -c '^pr checks' "$GH_LOG")" -eq 1 ] || { echo "FAIL red: want one pr checks read"; cat "$GH_LOG"; exit 1; }
  grep '^pr ' "$GH_LOG" | grep -vq -e ' -R o/r ' && { echo "FAIL red: a gh call without the known repository"; cat "$GH_LOG"; exit 1; }
  # V3: pending, no checks, head mismatch and a failed gh call are all red, each named.
  gate pend pending st.json --gate-mode ci --final; vetoed pend pending
  gate none nochecks st.json --gate-mode ci --final; vetoed none no_checks
  gate mism mismatch st.json --gate-mode ci --final; vetoed mism head_mismatch
  gate err error st.json --gate-mode ci --final; vetoed err gh_error
  gate nopr pass st-nopr.json --gate-mode ci --final; vetoed nopr no_pr
  # V10: a cancelled check is red, checks that were all skipped passed nothing, and a PR head
  # that moves while its green checks are read is red.
  gate canc cancel st.json --gate-mode ci --final; vetoed canc failed
  gate skipd skipping st.json --gate-mode ci --final; vetoed skipd no_checks
  gate moved moved st.json --gate-mode ci --final; vetoed moved head_mismatch
  jq -e '.gates[-1].detail|test("moved during the read")' "$(R moved)" >/dev/null || { echo "FAIL moved: detail"; jq -c '.gates[-1]' "$(R moved)"; exit 1; }
  # V4: CI green on the head -> the veto is green and the local suite still ran.
  gate green pass st.json --gate-mode ci --final
  jq -e '.gate_mode=="local" and .gates[0].name=="regression" and .gates[0].result=="green"
    and (.gates[-1] | .name=="ci-final-veto" and .result=="green" and .exit_code_branch==0 and .ci_status=="passed")
    and ([.gates[] | select(.result!="green")] | length==0)' "$(R green)" >/dev/null || { echo "FAIL green"; jq -c .gates "$(R green)"; exit 1; }
  "$ROOT/scripts/terminal-pairing.sh" --gate "$(R green)" --review-sha "$SHA" > "$TMP/pair.out" 2>&1 \
    || { echo "FAIL green: pairing refused a green local suite with a green veto: $(cat "$TMP/pair.out")"; exit 1; }
  # V7: with no regression runner anywhere the local gate is absent; a green veto must not
  # make the final gate count as one where a gate ran (an extra veto, never a stand-in).
  W2="$TMP/wt2"; mkdir -p "$W2"
  git -C "$W2" init -q -b main; git -C "$W2" config user.email t@t; git -C "$W2" config user.name t
  echo a > "$W2/a"; git -C "$W2" add -A; git -C "$W2" commit -qm base
  BASE2=$(git -C "$W2" rev-parse HEAD)
  git -C "$W2" checkout -q -b feat; echo c > "$W2/f"; git -C "$W2" add -A; git -C "$W2" commit -qm c1
  SHA2=$(git -C "$W2" rev-parse HEAD)
  W1="$W"; BASE1="$BASE"; W="$W2"; BASE="$BASE2"
  gate absent pass st.json --gate-mode ci --final
  W="$W1"; BASE="$BASE1"
  jq -e '.gates[0].name=="regression" and .gates[0].result=="absent" and .gates[0].exit_code_branch==null
    and (.gates[-1] | .name=="ci-final-veto" and .result=="green" and .ci_status=="passed")
    and ([.gates[] | select(.result!="absent" and .ci_veto!=true)] | length==0)' "$(R absent)" >/dev/null \
    || { echo "FAIL absent: precondition (regression absent, veto green) not met"; jq -c .gates "$(R absent)"; exit 1; }
  "$ROOT/scripts/terminal-pairing.sh" --gate "$(R absent)" --review-sha "$SHA2" > "$TMP/pair.out" 2>&1; rc=$?
  [ "$rc" -eq 1 ] && grep -Fq 'no gate ran (absent: regression; a ci-final-veto record never counts as a gate that ran)' "$TMP/pair.out" \
    || { echo "FAIL absent: pairing did not discard an absent local suite with a green veto (exit $rc): $(cat "$TMP/pair.out")"; exit 1; }
  # V7b: the veto record alone, with no other gate recorded, is no gate that ran either.
  mkdir "$TMP/lone"; jq '.gates |= [.[-1]]' "$(R green)" > "$(R lone)"
  "$ROOT/scripts/terminal-pairing.sh" --gate "$(R lone)" --review-sha "$SHA" > "$TMP/pair.out" 2>&1; rc=$?
  [ "$rc" -eq 1 ] && grep -Fq 'no gate ran (no other gate recorded; a ci-final-veto record never counts as a gate that ran)' "$TMP/pair.out" \
    || { echo "FAIL lone: pairing did not discard a lone green veto (exit $rc): $(cat "$TMP/pair.out")"; exit 1; }
  # V9: no repository known (no -R), the gate started from a directory that belongs to
  # another repository holding the same commit, whose CI is green: gh must run in the
  # worktree, whose own CI is red. Every gh call runs there.
  git clone -q "$W" "$TMP/other" 2>/dev/null; git -C "$TMP/other" checkout -q feat
  : > "$FK/cwd.log"
  cd "$TMP/other" || exit 1
  gate cwd cwd st-norepo.json --gate-mode ci --final
  cd "$ROOT" || exit 1
  vetoed cwd failed
  [ "$(sort -u "$FK/cwd.log")" = "$(cd "$W" && pwd -P)" ] || { echo "FAIL cwd: gh ran outside the worktree"; sort "$FK/cwd.log" | uniq -c; exit 1; }
  # V8: no gh on PATH (a PATH of links to every system tool but gh, so a /usr/bin/gh is
  # hidden too): the veto is red gh_missing and pairing discards the final gate.
  NOGH="$TMP/nogh"; mkdir "$NOGH"
  for t in python3 git jq; do ln -s "$(command -v "$t")" "$NOGH/$t"; done
  for d in /usr/bin /bin /usr/sbin /sbin; do [ -d "$d" ] && ln -s "$d"/* "$NOGH"/ 2>/dev/null; done
  rm -f "$NOGH/gh"
  PATH="$NOGH" sh -c 'command -v gh' >/dev/null 2>&1 && { echo "FAIL nogh: gh still on the test PATH"; exit 1; }
  printf 'pass' > "$FK/mode"; mkdir "$TMP/nogh-out"
  PATH="$NOGH" "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates '[]' --state-json "$TMP/st.json" --out "$TMP/nogh-out" --ci-poll 1 --ci-timeout 3 \
    --gate-mode ci --final 2>/dev/null
  vetoed nogh-out gh_missing
  if "$ROOT/scripts/terminal-pairing.sh" --gate "$(R nogh-out)" --review-sha "$SHA" > "$TMP/pair.out" 2>&1; then
    echo "FAIL nogh: pairing accepted a final gate whose CI could not be read"; exit 1; fi
  # V5: CI green never turns a local red green.
  touch "$FK/localred"
  gate lred pass st.json --gate-mode ci --final
  jq -e '.gates[0].name=="regression" and .gates[0].result=="red" and .gates[-1].result=="green"' "$(R lred)" >/dev/null || { echo "FAIL lred"; jq -c .gates "$(R lred)"; exit 1; }
  rm -f "$FK/localred"
  # V6: --gate-mode local --final and a non-final ci gate never get the veto; local mode calls no gh.
  gate loc fail st.json --gate-mode local --final
  jq -e '[.gates[] | select(.name=="ci-final-veto")] | length==0' "$(R loc)" >/dev/null || { echo "FAIL loc: veto in local mode"; exit 1; }
  [ ! -s "$GH_LOG" ] || { echo "FAIL loc: gh was called in local mode"; cat "$GH_LOG"; exit 1; }
  gate nonfinal pass st.json --gate-mode ci
  jq -e '.gate_mode=="ci" and [.gates[].name]==["ci"]' "$(R nonfinal)" >/dev/null || { echo "FAIL nonfinal"; jq -c .gates "$(R nonfinal)"; exit 1; }
  # V11 (#149): a check list too big for one command-line argument. The veto record used to
  # carry every check, and the record reaches python3 as an argument, so the final write died
  # with "Argument list too long" and an earlier green results file in the same --out paired.
  # Size: past getconf ARG_MAX (clamped to 128 KiB..4 MiB; Linux also caps one argument at
  # 128 KiB), every entry over 300 bytes, and measured below: one argument holding the
  # list must fail to exec here.
  AMAX=$(getconf ARG_MAX 2>/dev/null); case "$AMAX" in ''|*[!0-9]*) AMAX=2097152 ;; esac
  python3 - "$AMAX" "$FK" <<'PY'
  import json, sys
  amax, fk = int(sys.argv[1]), sys.argv[2]
  n = (min(max(amax, 131072), 4194304) + 65536) // 300 + 1
  def chk(i, b, name=None):
      return {"name": name or "matrix job %05d / ubuntu-26.04 / node 24" % i, "bucket": b, "state": "X",
              "workflow": "ci", "link": "https://github.com/acme/demo/actions/runs/45653339663/job/%012d?%s" % (i, "p" * 200)}
  ok = [chk(i, "pass") for i in range(n)]
  red = list(ok)
  for i in range(n - 28, n - 25):
      red[i] = chk(i, "pending")
  for i in range(n - 25, n):
      red[i] = chk(i, "fail", "x" * 300 if i == n - 25 else None)
  json.dump(ok, open(fk + "/big-pass.json", "w"))
  json.dump(red, open(fk + "/big-red.json", "w"))
  open(fk + "/n", "w").write(str(n))
  PY
  N=$(cat "$FK/n")
  if env true "$(cat "$FK/big-pass.json")" 2>/dev/null; then echo "FAIL big: $N checks still fit in one argument (ARG_MAX $AMAX)"; exit 1; fi
  # V11a: thousands of checks, 25 failed (the last ones, the first of them with a 300-character
  # name) and 3 pending: the results are written, the veto is red, and its record stays small.
  cp "$FK/big-red.json" "$FK/checks.json"
  gate bigred big st.json --gate-mode ci --final; rc=$?
  [ "$rc" -eq 0 ] && [ -s "$(R bigred)" ] || { echo "FAIL bigred: gate exit $rc, results not written"; exit 1; }
  vetoed bigred failed
  F2=$(printf 'matrix job %05d / ubuntu-26.04 / node 24' $((N - 24)))
  jq -e --argjson n "$N" --arg f2 "$F2" '.gates[-1] | (has("checks")|not) and .failed_count==25
    and .pending_count==3 and .checks_count==$n and (.failed|length)==20 and (.failed[0]|length)==200
    and .failed[1]==$f2 and (.pending|length)==3 and (.detail|test(" and 5 more$")) and (.detail|length)<=6000
    and ([.failed_count,.pending_count,.checks_count]|map(type)|unique)==["number"]' "$(R bigred)" >/dev/null \
    || { echo "FAIL bigred: veto record"; jq -c '.gates[-1]|del(.detail)' "$(R bigred)" | cut -c1-600; exit 1; }
  [ "$(wc -c < "$(R bigred)")" -lt 65536 ] || { echo "FAIL bigred: results file is not small"; exit 1; }
  if "$ROOT/scripts/terminal-pairing.sh" --gate "$(R bigred)" --review-sha "$SHA" > /dev/null 2>&1; then echo "FAIL bigred: pairing accepted it"; exit 1; fi
  # V11b: thousands of checks, all passed, local suite green: green veto, and pairing accepts it.
  cp "$FK/big-pass.json" "$FK/checks.json"
  gate bigok big st.json --gate-mode ci --final
  jq -e --argjson n "$N" '.gates[0].result=="green" and (.gates[-1] | .result=="green" and .ci_status=="passed"
    and .checks_count==$n and .failed_count==0 and .failed==[] and (has("checks")|not))' "$(R bigok)" >/dev/null \
    || { echo "FAIL bigok"; jq -c '.gates|map(del(.detail))' "$(R bigok)" | cut -c1-600; exit 1; }
  "$ROOT/scripts/terminal-pairing.sh" --gate "$(R bigok)" --review-sha "$SHA" > "$TMP/pair.out" 2>&1 \
    || { echo "FAIL bigok: pairing refused: $(cat "$TMP/pair.out")"; exit 1; }
  # V11c, the case found on #149: an earlier green final gate in the same --out (the diagnostic local
  # re-run), then the local suite goes red and the ci --final gate reads thousands of green
  # checks. Whatever this run writes, the earlier green file must not pair.
  gate bigstale pass st.json --gate-mode local --final
  "$ROOT/scripts/terminal-pairing.sh" --gate "$(R bigstale)" --review-sha "$SHA" >/dev/null 2>&1 \
    || { echo "FAIL bigstale: precondition, the earlier green result does not pair"; exit 1; }
  touch "$FK/localred"; cp "$FK/big-pass.json" "$FK/checks.json"
  gate bigstale big st.json --gate-mode ci --final
  if "$ROOT/scripts/terminal-pairing.sh" --gate "$(R bigstale)" --review-sha "$SHA" > "$TMP/pair.out" 2>&1; then
    echo "FAIL bigstale: an earlier green result paired after a red local suite: $(cat "$TMP/pair.out")"; exit 1; fi
  rm -f "$FK/localred"
  # V11d: an earlier green result, then a run whose results write fails for another reason (a
  # python3 first on PATH that refuses only that write): no results file is left, the gate
  # exits nonzero, and pairing has nothing to pair.
  gate wfail pass st.json --gate-mode local --final
  [ -s "$(R wfail)" ] || { echo "FAIL wfail: precondition, no earlier result"; exit 1; }
  SHIM="$TMP/pyshim"; mkdir "$SHIM"
  printf '#!/bin/sh\ncase "$1:$2" in -:*/integration-results.json) exit 1 ;; esac\nexec "%s" "$@"\n' "$(command -v python3)" > "$SHIM/python3"
  chmod +x "$SHIM/python3"
  PATH="$SHIM:$BIN:$PATH" "$GATE" --checkpoint-type integration --worktree-path "$W" --base-ref "$BASE" \
    --claimed-gates '[]' --state-json "$TMP/st.json" --out "$TMP/wfail" --gate-mode local --final 2>/dev/null; rc=$?
  [ "$rc" -ne 0 ] && [ ! -e "$(R wfail)" ] || { echo "FAIL wfail: gate exit $rc, results file left: $(ls "$TMP/wfail")"; exit 1; }
  if "$ROOT/scripts/terminal-pairing.sh" --gate "$(R wfail)" --review-sha "$SHA" >/dev/null 2>&1; then echo "FAIL wfail: pairing accepted"; exit 1; fi
  echo PASS
expected: exit 0; stdout "PASS". With --gate-mode ci --final and no project opt-in, the final gate runs the full local suite (gate_mode local, ci null, gates[0] the regression gate) and also reads `gh pr checks` once for the PR whose head is the worktree HEAD, recorded as a last gate "ci-final-veto" (not under-declared, reason appended "final gate CI veto: <status>"). A red check gives a red veto naming the failed check and head, which terminal-pairing.sh discards (V1), in a single read (V2); pending, no checks, head mismatch, a failed gh call and no known PR are each red with that status (V3); a cancelled check is red with status failed, checks that were all skipped with no_checks, and a PR head that moves while its green checks are read with head_mismatch (V10); a fully passed CI gives a green veto and pairing accepts it (V4) but never turns a red local suite green (V5); --gate-mode local --final calls no gh and a non-final ci gate is unchanged (V6). With no regression runner anywhere the local gate is absent and a green veto does not count as a gate that ran: terminal-pairing.sh discards with exit 1, "no gate ran (absent: regression; a ci-final-veto record never counts as a gate that ran)" (V7), and the same for a veto record with no other gate recorded (V7b). Both gh calls run in the worktree, so when no repository is known (no -R) the CI read is of the worktree's own repository even if the gate is started from another repository's directory holding the same commit with green CI (V9); a known repository is still passed as -R on every call (checked after V2). With no gh on PATH (a PATH of links to every system tool except gh, so it holds on hosts with /usr/bin/gh) the veto is red with ci_status gh_missing and pairing exits nonzero (V8). Mutation: skip the veto in the gate-mode resolver (scripts/integration-gate.sh) and V1 fails; record a pending read as green and V3 fails; drop the second head read, not count a cancelled check as failed, or count a skipped check as a pass, and V10 fails; count a ci_veto record as a gate that ran in terminal-pairing.sh and V7 and V7b fail; drop cwd=worktree from either gh call and V9 fails; drop -R from the gh calls and the check after V2 fails; return passed from the gh_missing branch and V8 fails. V11 (#149): the stub returns more checks than fit in one command-line argument (count from getconf ARG_MAX clamped to 128 KiB..4 MiB plus 64 KiB, at over 300 bytes a check; the row first checks that one argument holding the list fails to exec). With 25 failed and 3 pending the results are written and the veto is red with failed_count 25, pending_count 3, checks_count the full count, 20 failed names with a long name cut to 200 characters, detail ending "and 5 more", no checks list and a results file under 64 KiB, and pairing refuses it (V11a); all passed gives a green veto that pairs (V11b); an earlier green --gate-mode local --final result in the same --out does not pair once the local suite is red and the ci --final gate reads that list (V11c); and after an earlier green result, a run whose results write fails another way (a python3 first on PATH that refuses only that write) exits nonzero and leaves no results file (V11d). Mutation: keep the full check list in the veto record and V11a and V11b fail (V11c still passes: the earlier file is removed, so the failed write leaves nothing to pair); drop the removal of an earlier results file and V11d fails (V11c still passes: the bounded record is written); store a count as a string, or drop the name or list cap, and V11a fails.
