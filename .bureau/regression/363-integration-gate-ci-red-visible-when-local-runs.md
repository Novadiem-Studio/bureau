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
  m=$(cat "$FK/mode" 2>/dev/null)
  case "$1 $2" in
    "pr view")
      if [ "$m" = mismatch ]; then echo 0000000000000000000000000000000000000000; else git -C "$W" rev-parse HEAD; fi; exit 0 ;;
    "pr checks")
      case "$m" in
        nochecks) echo "no checks reported on the 'feat' branch" >&2; exit 1 ;;
        error) echo "HTTP 502: Bad Gateway" >&2; exit 1 ;;
        *) printf '[{"name":"tests","bucket":"%s","state":"X","workflow":"ci","link":""}]\n' "$m"; exit 0 ;;
      esac ;;
  esac
  exit 1
  FAKEGH
  chmod +x "$BIN/gh"
  printf '{"scope":{},"git":{"pr_number":7,"github_repo":"o/r"}}\n' > "$TMP/st.json"
  printf '{"scope":{},"git":{"pr_number":null}}\n' > "$TMP/st-nopr.json"
  gate() {  # <case> <mode> <state> <extra args...>
    c="$1"; printf '%s' "$2" > "$FK/mode"; st="$3"; shift 3
    mkdir "$TMP/$c"; : > "$GH_LOG"
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
  # V3: pending, no checks, head mismatch and a failed gh call are all red, each named.
  gate pend pending st.json --gate-mode ci --final; vetoed pend pending
  gate none nochecks st.json --gate-mode ci --final; vetoed none no_checks
  gate mism mismatch st.json --gate-mode ci --final; vetoed mism head_mismatch
  gate err error st.json --gate-mode ci --final; vetoed err gh_error
  gate nopr pass st-nopr.json --gate-mode ci --final; vetoed nopr no_pr
  # V4: CI green on the head -> the veto is green and the local suite still ran.
  gate green pass st.json --gate-mode ci --final
  jq -e '.gate_mode=="local" and .gates[0].name=="regression" and .gates[0].result=="green"
    and (.gates[-1] | .name=="ci-final-veto" and .result=="green" and .exit_code_branch==0 and .ci_status=="passed")
    and ([.gates[] | select(.result!="green")] | length==0)' "$(R green)" >/dev/null || { echo "FAIL green"; jq -c .gates "$(R green)"; exit 1; }
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
  echo PASS
expected: exit 0; stdout "PASS". With --gate-mode ci --final and no project opt-in, the final gate runs the full local suite (gate_mode local, ci null, gates[0] the regression gate) and also reads `gh pr checks` once for the PR whose head is the worktree HEAD, recorded as a last gate "ci-final-veto" (not under-declared, reason appended "final gate CI veto: <status>"). A red check gives a red veto naming the failed check and head, which terminal-pairing.sh discards (V1), in a single read (V2); pending, no checks, head mismatch, a failed gh call and no known PR are each red with that status (V3); a fully passed CI gives a green veto (V4) but never turns a red local suite green (V5); --gate-mode local --final calls no gh and a non-final ci gate is unchanged (V6). Mutation: skip the veto in the gate-mode resolver (scripts/integration-gate.sh) and V1 fails; record a pending read as green and V3 fails.
