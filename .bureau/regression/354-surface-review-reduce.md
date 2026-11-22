name: surface-review-reduce.py enforces the findings file (C1), the closure packet (C1b) and the reduce CLI (C2) for the parallel surface review
owner: scripts/surface-review-reduce.py; plan C1, C1b, C2 of run 20261121-parallel-surface-review (issue #143)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  PY="$ROOT/scripts/surface-review-reduce.py"
  T=$(mktemp -d)
  pass=0; fail=0
  # The guard runs on EXIT, so a run cut short (a truncated command block, a crash)
  # still fails on the PASS count instead of exiting 0.
  finish() {
    rm -rf "$T"
    if [ "$fail" -eq 0 ] && [ "$pass" -eq 77 ]; then
      echo "ALL PASS ($pass cases)"
    else
      echo "FAIL guard: pass=$pass fail=$fail, want pass=77 fail=0"; exit 1
    fi
  }
  trap finish EXIT
  trap 'exit 1' INT TERM
  ok() { echo "PASS $1"; pass=$((pass + 1)); }
  no() { echo "FAIL $1: $2"; fail=$((fail + 1)); }
  SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  OTHER=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  FIRED='["S1","S4"]'
  red() { "$PY" "$@" </dev/null >"$T/out" 2>"$T/err"; }
  mut() { jq "$2" "$1" >"$T/m" </dev/null && mv "$T/m" "$1"; }
  wrote() {
    for w in "$1"/merged.json "$1"/final.json "$1"/closure-*.json; do [ -e "$w" ] && return 0; done
    return 1
  }
  # bad <case> <exit> <file named> <rule keyword> <stage> <round-dir> [args...]
  bad() {
    c=$1; want=$2; nm=$3; kw=$4; shift 4; rd=$2
    red "$@"; rc=$?
    if [ "$rc" -ne "$want" ]; then no "$c" "exit $rc, want $want: $(head -1 "$T/err")"
    elif wrote "$rd"; then no "$c" "wrote a record on exit $rc"
    elif [ "$(wc -l <"$T/err" | tr -d ' ')" != 1 ]; then no "$c" "stderr is not one line"
    elif ! grep -qF -- "$nm" "$T/err"; then no "$c" "stderr does not name $nm: $(cat "$T/err")"
    elif ! grep -qF -- "$kw" "$T/err"; then no "$c" "stderr lacks '$kw': $(cat "$T/err")"
    else ok "$c"; fi
  }
  # stdout_ok <case> <record> <rN> <stage> [route]: the one C2 stdout line, F and B from the record.
  stdout_ok() {
    want="surface-review $3 $4: $(jq '.findings | length' "$2") findings, $(jq '.counts.blocker' "$2") blockers${5:+, route $5}"
    if [ "$(wc -l <"$T/out" | tr -d ' ')" = 1 ] && [ "$(cat "$T/out")" = "$want" ]; then ok "$1"
    else no "$1" "stdout '$(cat "$T/out")', want '$want'"; fi
  }
  # fj <path> <lens> <round> <findings, comma-joined> [closures] [gate_miss] [fired]
  fj() {
    printf '{"schema":"surface-findings/1","attempt_id":"challenger-t-%s-r%s","lens":"%s","round":%s,"diff_sha":"%s","fired":%s,"gate_miss":%s,"closures":%s,"findings":[%s]}\n' \
      "$2" "$3" "$2" "$3" "$SHA" "${7:-$FIRED}" "${6:-[]}" "${5:-[]}" "$4" >"$1"
  }
  # fd <id> <surface> <file> <line> <severity> [interacts] [reraises]
  fd() {
    printf '{"id":"%s","surface":"%s","file":"%s","line":%s,"failure_scenario":"Scenario for %s.","severity":"%s","verdict":"confirmed","interacts":%s,"reraises":%s}' \
      "$1" "$2" "$3" "$4" "$1" "$5" "${6:-[]}" "${7:-null}"
  }
  cl() { printf '[{"id":"%s","file":"%s","line":%s,"evidence":"Fixed at the cited line."}]' "$1" "$2" "$3"; }
  # mk_round <dir>: a valid round 1, fired S1,S4: an S1 warning, an S4 blocker, an X warning.
  mk_round() {
    mkdir -p "$1"
    cat >"$1/lens-s1.json" <<EOF
  {"schema":"surface-findings/1","attempt_id":"challenger-lens-s1-r1","lens":"S1","round":1,
    "diff_sha":"$SHA","fired":["S1","S4"],"gate_miss":[],"closures":[],
    "findings":[{"id":"r1-S1-1","surface":"S1","file":"app/a.py","line":10,
      "failure_scenario":"A retried write lands twice.","severity":"warning",
      "verdict":"plausible","interacts":[],"reraises":null}]}
  EOF
    cat >"$1/lens-s4.json" <<EOF
  {"schema":"surface-findings/1","attempt_id":"challenger-lens-s4-r1","lens":"S4","round":1,
    "diff_sha":"$SHA","fired":["S1","S4"],"gate_miss":[],"closures":[],
    "findings":[{"id":"r1-S4-1","surface":"S4","file":"app/b.py","line":20,
      "failure_scenario":"The webhook fires before commit; on rollback the partner still books.",
      "severity":"blocker","verdict":"confirmed","interacts":[],"reraises":null}]}
  EOF
    cat >"$1/interaction.json" <<EOF
  {"schema":"surface-findings/1","attempt_id":"challenger-interaction-r1","lens":"X","round":1,
    "diff_sha":"$SHA","fired":["S1","S4"],"gate_miss":[],"closures":[],
    "findings":[{"id":"r1-X-1","surface":"X","file":"app/c.py","line":30,
      "failure_scenario":"The retried write and the early webhook combine into two bookings.",
      "severity":"warning","verdict":"plausible","interacts":["S1","S4"],"reraises":null}]}
  EOF
  }
  # mk_r2 <dir>: r1 from mk_round reduced to route fix (rerun_lenses S4); a valid r2 where
  # lens-s4.json closes r1-S4-1 and interaction.json has nothing to close.
  mk_r2() {
    mk_round "$1/r1"
    red final "$1/r1" --lenses S1,S4 --diff-sha "$SHA" --max-fix-rounds 2 || return 1
    mkdir -p "$1/r2"
    fj "$1/r2/lens-s4.json" S4 2 "" "$(cl r1-S4-1 app/b.py 21)"
    fj "$1/r2/interaction.json" X 2 ""
  }

  # (a) two lenses flag the same file:line: one entry, surfaces union, severity blocker.
  mk_round "$T/a/r1"
  mut "$T/a/r1/lens-s1.json" '.findings[0].file = "app/b.py" | .findings[0].line = 20'
  if red lenses "$T/a/r1" --lenses S1,S4 --diff-sha "$SHA" &&
    jq -e '(.findings | length) == 1 and .findings[0].surfaces == ["S1","S4"]
      and .findings[0].severity == "blocker" and .findings[0].ids == ["r1-S1-1","r1-S4-1"]
      and .findings[0].verdict == "confirmed" and .schema == "surface-merged/1"' "$T/a/r1/merged.json" >/dev/null
  then ok a; else no a "same file:line did not merge into one blocker: $(cat "$T/err")"; fi
  stdout_ok a-stdout "$T/a/r1/merged.json" r1 lenses

  # (b) the same inputs created in opposite order, in different dirs: byte-identical merged.json.
  mk_round "$T/b0/r1"
  mut "$T/b0/r1/lens-s1.json" '.findings += [.findings[0] | .id = "r1-S1-2" | .file = "app/0.py" | .line = 3]'
  mkdir -p "$T/b1/r1" "$T/b2/r1"
  for f in lens-s1.json lens-s4.json; do cp "$T/b0/r1/$f" "$T/b1/r1/$f"; done
  for f in lens-s4.json lens-s1.json; do cp "$T/b0/r1/$f" "$T/b2/r1/$f"; done
  if red lenses "$T/b1/r1" --lenses S1,S4 --diff-sha "$SHA" && red lenses "$T/b2/r1" --lenses S1,S4 --diff-sha "$SHA" &&
    cmp -s "$T/b1/r1/merged.json" "$T/b2/r1/merged.json" &&
    jq -e '[.findings[].file] == ["app/0.py","app/a.py","app/b.py"]' "$T/b1/r1/merged.json" >/dev/null
  then ok b; else no b "merged.json differs by input order or is unsorted"; fi

  # (c) missing lens-s4.json: exit 3 naming S4, nothing written.
  mk_round "$T/c/r1"; rm "$T/c/r1/lens-s4.json"
  bad c 3 "r1/lens-s4.json" "lens S4" lenses "$T/c/r1" --lenses S1,S4 --diff-sha "$SHA"

  # (d) diff_sha mismatch: exit 2, nothing written.
  mk_round "$T/d/r1"
  bad d 2 "r1/lens-s1.json" "diff_sha" lenses "$T/d/r1" --lenses S1,S4 --diff-sha "$OTHER"

  # (e) empty lens files plus an X blocker on S4+S5: route fix, both lenses re-run, three packets.
  F45='["S4","S5"]'
  mkdir -p "$T/e/r1"
  fj "$T/e/r1/lens-s4.json" S4 1 "" "" "" "$F45"
  fj "$T/e/r1/lens-s5.json" S5 1 "" "" "" "$F45"
  fj "$T/e/r1/interaction.json" X 1 "$(fd r1-X-1 X app/c.py 7 blocker "$F45")" "" "" "$F45"
  if red final "$T/e/r1" --lenses S4,S5 --diff-sha "$SHA" --max-fix-rounds 2 &&
    jq -e '.route == "fix" and .rerun_lenses == ["S4","S5"] and .rerun_interaction == true
      and .findings[0].surfaces == ["S4","S5","X"] and .schema == "surface-final/1"' "$T/e/r1/final.json" >/dev/null &&
    jq -e '.schema == "surface-closure/1" and .from_round == 1 and .lens == "S4" and .blockers == []' "$T/e/r1/closure-s4.json" >/dev/null &&
    jq -e '.lens == "S5" and .blockers == []' "$T/e/r1/closure-s5.json" >/dev/null &&
    jq -e '.lens == "X" and [.blockers[].id] == ["r1-X-1"]' "$T/e/r1/closure-x.json" >/dev/null
  then ok e; else no e "X blocker did not route fix with packets: $(cat "$T/err")"; fi
  stdout_ok e-stdout "$T/e/r1/final.json" r1 final fix

  # (f) a gate miss with an open blocker routes escalate.
  mk_round "$T/f/r1"
  mut "$T/f/r1/lens-s1.json" '.gate_miss = ["S3"]'
  if red final "$T/f/r1" --lenses S1,S4 --diff-sha "$SHA" --max-fix-rounds 2 &&
    jq -e '.route == "escalate" and .gate_miss == ["S3"] and .rerun_lenses == [] and .rerun_interaction == false' "$T/f/r1/final.json" >/dev/null
  then ok f; else no f "gate_miss did not route escalate"; fi

  # (g) r3 with an open blocker and --max-fix-rounds 2: checkpoint, no packets.
  mk_r2 "$T/g"
  fj "$T/g/r2/lens-s4.json" S4 2 "$(fd r2-S4-1 S4 app/b.py 20 blocker "" '"r1-S4-1"')"
  mkdir -p "$T/g/r3"
  fj "$T/g/r3/lens-s4.json" S4 3 "$(fd r3-S4-1 S4 app/b.py 20 blocker "" '"r2-S4-1"')"
  fj "$T/g/r3/interaction.json" X 3 ""
  if red final "$T/g/r2" --lenses S4 --diff-sha "$SHA" --max-fix-rounds 2 &&
    jq -e '.route == "fix" and .rerun_lenses == ["S4"]' "$T/g/r2/final.json" >/dev/null &&
    red final "$T/g/r3" --lenses S4 --diff-sha "$SHA" --max-fix-rounds 2 &&
    jq -e '.route == "checkpoint" and .max_fix_rounds == 2 and .rerun_lenses == []' "$T/g/r3/final.json" >/dev/null &&
    ! ls "$T/g/r3"/closure-*.json >/dev/null 2>&1
  then ok g; else no g "K >= M did not route checkpoint: $(cat "$T/err")"; fi

  # (h) an override of that blocker: ship, id in overridden_ids.
  printf '{"overrides":[{"id":"r3-S4-1","reason":"Accepted: the partner dedupes on order id."}]}\n' >"$T/g/overrides.json"
  if red final "$T/g/r3" --lenses S4 --diff-sha "$SHA" --max-fix-rounds 2 --overrides "$T/g/overrides.json" &&
    jq -e '.route == "ship" and .findings[0].overridden_ids == ["r3-S4-1"]
      and .findings[0].severity == "warning" and .counts.blocker == 0' "$T/g/r3/final.json" >/dev/null
  then ok h; else no h "override did not route ship: $(cat "$T/err")"; fi

  # (p) checkpoint option C: re-run final on r3 with --max-fix-rounds 3: fix, packets written.
  if red final "$T/g/r3" --lenses S4 --diff-sha "$SHA" --max-fix-rounds 3 &&
    jq -e '.route == "fix" and .rerun_lenses == ["S4"] and .max_fix_rounds == 3' "$T/g/r3/final.json" >/dev/null &&
    jq -e '.from_round == 3 and [.blockers[].id] == ["r3-S4-1"]' "$T/g/r3/closure-s4.json" >/dev/null &&
    jq -e '.blockers == []' "$T/g/r3/closure-x.json" >/dev/null
  then ok p; else no p "raised cap did not route fix with packets: $(cat "$T/err")"; fi

  # (i) r2 where lens-s4.json neither closes nor re-raises r1-S4-1: exit 2 naming it.
  mk_r2 "$T/i"; fj "$T/i/r2/lens-s4.json" S4 2 ""
  bad i 2 "r2/lens-s4.json" "r1-S4-1: neither closed nor re-raised" lenses "$T/i/r2" --lenses S4 --diff-sha "$SHA"

  # (j) the same round with a closure for r1-S4-1 and no findings: ship.
  mk_r2 "$T/j"
  if red final "$T/j/r2" --lenses S4 --diff-sha "$SHA" --max-fix-rounds 2 &&
    jq -e '.route == "ship" and .findings == [] and [.closed[] | .id + ":" + .lens] == ["r1-S4-1:S4"]' "$T/j/r2/final.json" >/dev/null
  then ok j; else no j "a closed blocker did not route ship: $(cat "$T/err")"; fi

  # (k) r2 with --lenses S1 when the prior rerun_lenses is S4: exit 2 naming S4.
  mk_r2 "$T/k"; rm "$T/k/r2/lens-s4.json"; fj "$T/k/r2/lens-s1.json" S1 2 ""
  bad k 2 "r1/final.json" "skips S4" lenses "$T/k/r2" --lenses S1 --diff-sha "$SHA"

  # (l) readiness-only fix round: an R blocker re-runs only the interaction reviewer.
  mkdir -p "$T/l/r1"
  fj "$T/l/r1/lens-s1.json" S1 1 ""; fj "$T/l/r1/lens-s4.json" S4 1 ""
  fj "$T/l/r1/interaction.json" X 1 "$(fd r1-X-1 R app/r.py 3 blocker)"
  if red final "$T/l/r1" --lenses S1,S4 --diff-sha "$SHA" --max-fix-rounds 2 &&
    jq -e '.route == "fix" and .rerun_lenses == [] and .rerun_interaction == true and .findings[0].surfaces == ["R"]' "$T/l/r1/final.json" >/dev/null &&
    jq -e '[.blockers[].id] == ["r1-X-1"]' "$T/l/r1/closure-x.json" >/dev/null &&
    ! ls "$T/l/r1"/closure-s*.json >/dev/null 2>&1
  then ok l1; else no l1 "R blocker did not route a readiness-only fix: $(cat "$T/err")"; fi
  mkdir -p "$T/l/r2"
  if red lenses "$T/l/r2" --lenses none --diff-sha "$SHA" &&
    jq -e '.lenses == [] and .findings == [] and .counts == {"blocker":0,"warning":0} and .fired == ["S1","S4"]' "$T/l/r2/merged.json" >/dev/null
  then ok l2; else no l2 "lenses --lenses none did not write the empty merge: $(cat "$T/err")"; fi
  fj "$T/l/r2/interaction.json" X 2 "" "$(cl r1-X-1 app/r.py 4)"
  if red final "$T/l/r2" --lenses none --diff-sha "$SHA" --max-fix-rounds 2 &&
    jq -e '.route == "ship"' "$T/l/r2/final.json" >/dev/null
  then ok l3; else no l3 "closing the R blocker did not route ship: $(cat "$T/err")"; fi

  # (m) --lenses none in r1 and after a prior rerun_lenses of S4, and an empty --lenses: exit 2.
  mk_round "$T/m1/r1"
  bad m1 2 "arguments" "--lenses none" lenses "$T/m1/r1" --lenses none --diff-sha "$SHA"
  mk_r2 "$T/m2"
  bad m2 2 "r1/final.json" "--lenses none needs rerun_lenses []" lenses "$T/m2/r2" --lenses none --diff-sha "$SHA"
  mk_round "$T/m3/r1"
  bad m3 2 "arguments" "--lenses is empty" lenses "$T/m3/r1" --lenses "" --diff-sha "$SHA"

  # (n) a lens added in r2 has no packet: closures [] passes, a closure fails; a required packet missing is exit 3.
  mk_r2 "$T/n"; fj "$T/n/r2/lens-s1.json" S1 2 ""
  if red lenses "$T/n/r2" --lenses S1,S4 --diff-sha "$SHA" &&
    jq -e '.lenses == ["S1","S4"]' "$T/n/r2/merged.json" >/dev/null
  then ok n1; else no n1 "an added lens with closures [] was refused: $(cat "$T/err")"; fi
  rm -f "$T/n/r2/merged.json"
  fj "$T/n/r2/lens-s1.json" S1 2 "" "$(cl r1-S1-1 app/a.py 10)"
  bad n2 2 "r2/lens-s1.json" "not in closure packet" lenses "$T/n/r2" --lenses S1,S4 --diff-sha "$SHA"
  fj "$T/n/r2/lens-s1.json" S1 2 ""; rm "$T/n/r1/closure-s4.json"
  bad n3 3 "r1/closure-s4.json" "missing closure packet" lenses "$T/n/r2" --lenses S1,S4 --diff-sha "$SHA"

  # (o) check order: prior final.json and a current lens file both missing: exit 3 names the prior one.
  mk_r2 "$T/o"; rm "$T/o/r1/final.json" "$T/o/r2/lens-s4.json"
  bad o 3 "r1/final.json" "missing" lenses "$T/o/r2" --lenses S4 --diff-sha "$SHA"

  # (q) invalid input, one row per rule. Each row starts from a valid round (r1 = mk_round,
  # r2 = mk_r2), applies one jq mutation to one file, runs the stage, and wants exit 2,
  # nothing written, and one stderr line naming the file and the rule keyword.
  # label~base~stage~file~jq mutation~stderr rule keyword
  while IFS='~' read -r label base stage file filter kw; do
    [ -n "$label" ] || continue
    d="$T/q-$label"
    if [ "$base" = r2 ]; then mk_r2 "$d"; rd="$d/r2"; lz=S4; else mk_round "$d/r1"; rd="$d/r1"; lz=S1,S4; fi
    if ! mut "$rd/$file" "$filter"; then no "q-$label" "jq mutation failed"; continue; fi
    if [ "$stage" = final ]; then
      bad "q-$label" 2 "${rd##*/}/$file" "$kw" final "$rd" --lenses "$lz" --diff-sha "$SHA" --max-fix-rounds 2
    else
      bad "q-$label" 2 "${rd##*/}/$file" "$kw" lenses "$rd" --lenses "$lz" --diff-sha "$SHA"
    fi
  done <<'ROWS'
  top-unknown-key~r1~lenses~lens-s1.json~.extra = 1~unknown key 'extra' in the top level
  finding-unknown-key~r1~lenses~lens-s1.json~.findings[0].extra = 1~unknown key 'extra' in finding 0
  closure-unknown-key~r2~lenses~lens-s4.json~.closures[0].extra = 1~unknown key 'extra' in closure entry 0
  schema~r1~lenses~lens-s1.json~.schema = "surface-findings/2"~schema must be surface-findings/1
  attempt-id~r1~lenses~lens-s1.json~.attempt_id = "lens-s1-r1"~attempt_id must start with challenger-
  lens-vs-filename~r1~lenses~lens-s1.json~.lens = "S4"~lens must be S1
  interaction-lens~r1~final~interaction.json~.lens = "S1"~lens must be X
  round-vs-dir~r1~lenses~lens-s1.json~.round = 2~round must be 1
  fired-one~r1~lenses~lens-s1.json~.fired = ["S1"]~fired must be exactly two distinct S-ids
  fired-three~r1~lenses~lens-s1.json~.fired = ["S1","S4","S5"]~fired must be exactly two distinct S-ids
  fired-duplicate~r1~lenses~lens-s1.json~.fired = ["S1","S1"]~fired must be exactly two distinct S-ids
  fired-nested~r1~lenses~lens-s1.json~.fired = [["S1"],"S4"]~fired must be exactly two distinct S-ids
  fired-differs~r1~lenses~lens-s4.json~.fired = ["S2","S4"]~fired differs from r1/lens-s1.json
  lens-not-in-fired~r1~lenses~lens-s1.json~.fired = ["S2","S4"]~lens S1 not in fired
  gate-miss-in-fired~r1~lenses~lens-s1.json~.gate_miss = ["S1"]~gate_miss S1 is in fired
  gate-miss-nested~r1~lenses~lens-s1.json~.gate_miss = [["S3"]]~gate_miss must be distinct S-ids
  id-round-prefix~r1~lenses~lens-s1.json~.findings[0].id = "r2-S1-1"~wrong round prefix
  id-lens~r1~lenses~lens-s1.json~.findings[0].id = "r1-S2-1"~id lens of 'r1-S2-1' must be S1
  id-number-zero~r1~lenses~lens-s1.json~.findings[0].id = "r1-S1-0"~id number of 'r1-S1-0' must be >= 1
  id-duplicate~r1~lenses~lens-s1.json~.findings += [.findings[0]]~duplicate id 'r1-S1-1'
  surface-not-lens~r1~lenses~lens-s1.json~.findings[0].surface = "S4"~must equal lens S1
  surface-x-in-lens~r1~lenses~lens-s1.json~.findings[0].surface = "X"~must equal lens S1
  surface-r-in-lens~r1~lenses~lens-s1.json~.findings[0].surface = "R"~must equal lens S1
  interaction-surface~r1~final~interaction.json~.findings[0].surface = "S1"~must be X or R
  file-absolute~r1~lenses~lens-s1.json~.findings[0].file = "/app/a.py"~must be repo-relative
  file-dotdot~r1~lenses~lens-s1.json~.findings[0].file = "app/../a.py"~must be repo-relative
  line-zero~r1~lenses~lens-s1.json~.findings[0].line = 0~line must be an integer >= 1
  line-negative~r1~lenses~lens-s1.json~.findings[0].line = -3~line must be an integer >= 1
  line-string~r1~lenses~lens-s1.json~.findings[0].line = "10"~line must be an integer >= 1
  scenario-empty~r1~lenses~lens-s1.json~.findings[0].failure_scenario = ""~failure_scenario is empty
  severity-enum~r1~lenses~lens-s1.json~.findings[0].severity = "critical"~must be blocker or warning
  verdict-enum~r1~lenses~lens-s1.json~.findings[0].verdict = "maybe"~must be confirmed or plausible
  interacts-on-s~r1~lenses~lens-s1.json~.findings[0].interacts = ["S1","S4"]~interacts must be []
  x-interacts-one~r1~final~interaction.json~.findings[0].interacts = ["S1"]~must be two or more distinct S-ids
  x-interacts-duplicate~r1~final~interaction.json~.findings[0].interacts = ["S1","S1"]~must be two or more distinct S-ids
  x-interacts-not-fired~r1~final~interaction.json~.findings[0].interacts = ["S1","S2"]~interacts id S2
  x-interacts-nested~r1~final~interaction.json~.findings[0].interacts = [["S1"],"S4"]~must be two or more distinct S-ids
  reraises-on-warning~r1~lenses~lens-s1.json~.findings[0].reraises = "r1-S1-9"~reraises only allowed on a blocker
  reraises-round1~r1~lenses~lens-s4.json~.findings[0].reraises = "r0-S4-1"~reraises must be null in round 1
  closures-round1~r1~lenses~lens-s1.json~.closures = [{"id":"r0-S1-1","file":"app/a.py","line":1,"evidence":"x"}]~closures must be [] in round 1
  closure-evidence-empty~r2~lenses~lens-s4.json~.closures[0].evidence = ""~closure evidence is empty
  closed-and-reraised~r2~lenses~lens-s4.json~.findings = [{"id":"r2-S4-1","surface":"S4","file":"app/b.py","line":20,"failure_scenario":"Still fires early.","severity":"blocker","verdict":"confirmed","interacts":[],"reraises":"r1-S4-1"}]~r1-S4-1: both closed and re-raised
  closure-not-in-packet~r2~lenses~lens-s4.json~.closures += [{"id":"r1-S4-9","file":"app/b.py","line":22,"evidence":"Also fixed."}]~closure id 'r1-S4-9' not in closure packet
  ROWS

  # (q) rows that need more than a one-file mutation.
  mk_round "$T/q-unlisted-lens/r1"; cp "$T/q-unlisted-lens/r1/lens-s1.json" "$T/q-unlisted-lens/r1/lens-s5.json"
  bad q-unlisted-lens 2 "r1/lens-s5.json" "not in --lenses" lenses "$T/q-unlisted-lens/r1" --lenses S1,S4 --diff-sha "$SHA"
  mk_r2 "$T/q-prior-ship"; mut "$T/q-prior-ship/r1/final.json" '.route = "ship"'
  bad q-prior-ship 2 "r1/final.json" "route is ship, not fix" lenses "$T/q-prior-ship/r2" --lenses S4 --diff-sha "$SHA"
  mk_r2 "$T/q-prior-fired-nested"; mut "$T/q-prior-fired-nested/r1/final.json" '.fired = [["S1"],"S4"]'
  bad q-prior-fired-nested 2 "r1/final.json" "fired must be exactly two distinct S-ids" lenses "$T/q-prior-fired-nested/r2" --lenses S4 --diff-sha "$SHA"
  # A destination that cannot be replaced (a directory at final.json) is refused before the
  # closure packets, which come first in the write order, are replaced.
  mk_round "$T/q-dest-dir/r1"; mkdir "$T/q-dest-dir/r1/final.json"
  red final "$T/q-dest-dir/r1" --lenses S1,S4 --diff-sha "$SHA" --max-fix-rounds 2; rc=$?
  if [ "$rc" -eq 2 ] && [ -d "$T/q-dest-dir/r1/final.json" ] && ! ls "$T/q-dest-dir/r1"/closure-*.json >/dev/null 2>&1 &&
    grep -qF "r1/final.json: destination exists and is not a regular file" "$T/err"
  then ok q-dest-dir; else no q-dest-dir "exit $rc, partial write or wrong rule: $(cat "$T/err")"; fi
  mk_round "$T/q-mfr-missing/r1"
  bad q-mfr-missing 2 "arguments" "--max-fix-rounds is required" final "$T/q-mfr-missing/r1" --lenses S1,S4 --diff-sha "$SHA"
  mk_round "$T/q-mfr-nonint/r1"
  bad q-mfr-nonint 2 "arguments" "--max-fix-rounds must be a non-negative integer" final "$T/q-mfr-nonint/r1" --lenses S1,S4 --diff-sha "$SHA" --max-fix-rounds two
  mk_round "$T/q-dir-name/round1"
  bad q-dir-name 2 "round1" "must be named r<N>" lenses "$T/q-dir-name/round1" --lenses S1,S4 --diff-sha "$SHA"
  ov() { mk_round "$T/q-$1/r1"; printf '{"overrides":[{"id":"%s","reason":"%s"}]}\n' "$2" "$3" >"$T/q-$1/overrides.json"
    bad "q-$1" 2 "overrides.json" "$4" final "$T/q-$1/r1" --lenses S1,S4 --diff-sha "$SHA" --max-fix-rounds 2 --overrides "$T/q-$1/overrides.json"; }
  ov override-warning r1-S1-1 "Accepted." "override id 'r1-S1-1' is not a blocker finding in this round"
  ov override-not-in-round r1-S4-9 "Accepted." "override id 'r1-S4-9' is not a blocker finding in this round"
  ov override-empty-reason r1-S4-1 "" "override reason for 'r1-S4-1' is empty"

  [ "$fail" -eq 0 ] && [ "$pass" -eq 77 ]
  # Mutation note: each case line pins one rule of scripts/surface-review-reduce.py. Removing
  # the (file, line) merge or the surfaces union fails a; sorting by anything but (file, line),
  # or writing the round dir's path, fails b; dropping the missing-file exit 3 fails c; skipping
  # the diff_sha check fails d; dropping X interacts from rerun_lenses or the packet writes fails
  # e; letting gate_miss lose precedence fails f; dropping K >= M fails g; ignoring overrides
  # fails h; dropping the closure-accounting absent check fails i, and over-strict accounting
  # fails j; dropping the rerun_lenses superset rule fails k; refusing --lenses none or writing
  # closure-s packets for R blockers fails l1-l3; dropping the none-only-where-allowed rule or the
  # empty-value rule fails m1-m3; requiring a packet for an added lens fails n1, skipping its
  # empty-packet accounting fails n2, and dropping the required-packet exit 3 fails n3; checking
  # current-round files before the prior final.json fails o;
  # ignoring --max-fix-rounds on a re-run fails p; each q-<label> line fails when its rule in the
  # ROWS table (or the inline rows after it) is removed; changing the stdout template fails
  # a-stdout and e-stdout. The *-nested rows fail (a TypeError traceback, exit 1) when a set()
  # runs before the string check; q-dest-dir fails when the destination check before the first
  # replace is dropped. A column-0 line in the command block truncates it, and the EXIT guard
  # then fails on the PASS count.
expected: exit 0; the last stdout line is "ALL PASS (77 cases)"; 77 "PASS <case>" lines and no "FAIL" line. Covers cases (a)-(q) of prompt 01 and the stdout template on a and e.
phase: 01 · execute-plan (run 20261121-parallel-surface-review, issue #143)
