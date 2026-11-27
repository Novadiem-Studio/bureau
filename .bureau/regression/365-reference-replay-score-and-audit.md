name: reference-replay score + audit — anchor and pattern must match inside one finding; controls fail only on BLOCKED; any tool path outside the packet marks the trial contaminated
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  S="$ROOT/scripts/reference-replay.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  fail() { echo "FAIL: $1"; exit 1; }
  python3 - "$TMP" <<'PY'
  import json, os, sys
  t = sys.argv[1]
  def w(name, obj): json.dump(obj, open(os.path.join(t, name), "w"))
  w("miss.json", {"id": "toy", "kind": "known-miss",
                  "expected": [{"id": "e1", "anchor": "app.py", "pattern": "https|cleartext"}]})
  w("control.json", {"id": "toy-control", "kind": "control", "expected": []})
  cite = {"kind": "presence", "path": "app.py", "anchor": "def charge"}
  w("v-blocker.json", {"verdict": "BLOCKED", "warnings": [],
      "blockers": [{"id": "b1", "summary": "charge() posts the password in cleartext", "citation": cite}]})
  w("v-split.json", {"verdict": "APPROVED_WITH_WARNINGS", "blockers": [],
      "warnings": [{"id": "w1", "summary": "app.py grew long"}, {"id": "w2", "summary": "send credentials over https"}]})
  w("v-warning.json", {"verdict": "APPROVED_WITH_WARNINGS", "blockers": [],
      "warnings": [{"id": "w1", "summary": "app.py: charge() should require https"}]})
  w("v-approved.json", {"verdict": "APPROVED_WITH_WARNINGS", "blockers": [], "warnings": []})
  PY
  get() { python3 -c 'import json,sys;d=json.load(sys.stdin);print(eval(sys.argv[1],{"d":d}))' "$1"; }
  [ "$(bash "$S" score "$TMP/miss.json" "$TMP/v-blocker.json" | get 'd["pass"],d["all_as_blocker"]')" = "(True, True)" ] || fail "blocker match not scored as found-as-blocker"
  [ "$(bash "$S" score "$TMP/miss.json" "$TMP/v-split.json" | get 'd["pass"]')" = "False" ] || fail "anchor and pattern in different findings counted as found"
  [ "$(bash "$S" score "$TMP/miss.json" "$TMP/v-warning.json" | get 'd["pass"],d["all_as_blocker"]')" = "(True, False)" ] || fail "warning match not scored as found-not-as-blocker"
  [ "$(bash "$S" score "$TMP/control.json" "$TMP/v-blocker.json" | get 'd["pass"]')" = "False" ] || fail "BLOCKED control not counted as a false positive"
  [ "$(bash "$S" score "$TMP/control.json" "$TMP/v-approved.json" | get 'd["pass"]')" = "True" ] || fail "unblocked control not counted as a pass"
  # audit
  P="$TMP/packet"; mkdir -p "$P/tree"; RP=$(cd "$P" && pwd -P)
  ev() { python3 -c 'import json,sys
  print(json.dumps({"type":"assistant","message":{"content":[{"type":"tool_use","name":sys.argv[1],"input":json.loads(sys.argv[2])}]}}))' "$1" "$2"; }
  { ev Read '{"file_path":"tree/app.py"}'; ev Read "{\"file_path\":\"$RP/review.diff\"}"; ev Grep '{"pattern":"x"}'; ev StructuredOutput '{"verdict":"APPROVED"}'; } > "$TMP/clean.jsonl"
  [ "$(bash "$S" audit "$P" "$TMP/clean.jsonl" | get 'd["contaminated"],d["tool_calls"]')" = "(False, 4)" ] || fail "in-packet reads flagged"
  for bad in '{"file_path":"/etc/hosts"}' '{"file_path":"../outside.md"}'; do
    ev Read "$bad" > "$TMP/bad.jsonl"
    [ "$(bash "$S" audit "$P" "$TMP/bad.jsonl" | get 'd["contaminated"]')" = "True" ] || fail "escaping read not flagged: $bad"
  done
  ev Grep '{"pattern":"x","path":"/Users"}' > "$TMP/bad.jsonl"
  [ "$(bash "$S" audit "$P" "$TMP/bad.jsonl" | get 'd["contaminated"]')" = "True" ] || fail "escaping grep path not flagged"
  ev Bash '{"command":"ls"}' > "$TMP/bad.jsonl"
  [ "$(bash "$S" audit "$P" "$TMP/bad.jsonl" | get 'd["contaminated"]')" = "True" ] || fail "disallowed tool not flagged"
  echo PASS
expected: exit 0 and prints PASS — a blocker naming the anchor and matching the pattern scores found-as-blocker; anchor and pattern split across two findings scores not found; a single matching warning scores found but not as a blocker; a BLOCKED control fails and an unblocked control passes; the audit accepts relative and absolute reads inside the packet, a path-less Grep and the StructuredOutput call, and flags an absolute read outside, a ../ read, a Grep with an outside path and a non-read tool.
phase: #161 · reference replay
owner: scripts/reference-replay.sh score, audit
