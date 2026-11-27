name: reference-replay run — spawns a read-only claude -p in the packet with the sandbox flags, scores a clean trial, never scores a contaminated one (fake CLAUDE_BIN, no model spend)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  S="$ROOT/scripts/reference-replay.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  fail() { echo "FAIL: $1"; exit 1; }
  R="$TMP/repo"; git init -q "$R"
  git -C "$R" config user.email fixture@example.invalid; git -C "$R" config user.name fixture
  printf 'def ok():\n    return 1\n' > "$R/app.py"; git -C "$R" add -A; git -C "$R" commit -qm base
  B=$(git -C "$R" rev-parse HEAD)
  printf 'def charge(url, password):\n    return post(url, password)\n' >> "$R/app.py"; git -C "$R" commit -qam target
  T=$(git -C "$R" rev-parse HEAD)
  D=$(git -C "$R" diff "$B" "$T" | python3 -c 'import hashlib,sys;print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')
  python3 -c 'import json,sys
  json.dump({"id":"toy","kind":"known-miss","review_mode":"build-diff","target_repo":sys.argv[1],
             "base_sha":sys.argv[2],"target_sha":sys.argv[3],"diff_sha":sys.argv[4],"prompt_paths":[],
             "leak_patterns":["validate_https_url"],
             "expected":[{"id":"e1","anchor":"app.py","pattern":"cleartext"}]},open(sys.argv[5],"w"))' "$R" "$B" "$T" "$D" "$TMP/case.json"
  # A fake claude: records its argv and cwd, reads FAKE_READ, returns a verdict that finds e1.
  cat > "$TMP/fake-claude" <<'SH'
  #!/bin/sh
  printf '%s\n' "$PWD" > "$FAKE_LOG.cwd"
  for a in "$@"; do printf '%s\n' "$a"; done > "$FAKE_LOG.argv"
  python3 -c 'import json,os
  print(json.dumps({"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":os.environ["FAKE_READ"]}}]}}))
  v={"attempt_id":"replay","review_mode":"build-diff","reviewed_artifacts":[],"blocker_ids":["b1"],"timestamp":"2026-01-01T00:00:00Z",
     "blockers":[{"id":"b1","summary":"charge() sends the password in cleartext","citation":{"kind":"presence","path":"app.py","anchor":"def charge"}}],
     "warnings":[],"verdict":"BLOCKED"}
  print(json.dumps({"type":"result","subtype":"success","num_turns":3,"structured_output":v,
                    "usage":{"input_tokens":1000,"cache_creation_input_tokens":2000,"cache_read_input_tokens":5000,"output_tokens":300}}))'
  SH
  chmod +x "$TMP/fake-claude"
  export CLAUDE_BIN="$TMP/fake-claude" FAKE_LOG="$TMP/fake"
  # clean trial
  FAKE_READ=review.diff bash "$S" run "$TMP/case.json" "$TMP/out" --model opus >/dev/null || fail "clean run exited non-zero"
  TR=$(ls -d "$TMP"/out/toy/trial-* | head -1)
  [ "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["status"])' "$TR/trial.json")" = scored ] || fail "clean trial not scored"
  [ "$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["pass"],d["all_as_blocker"])' "$TR/score.json")" = "True True" ] || fail "clean trial score wrong"
  case "$(cat "$FAKE_LOG.cwd")" in */packet) ;; *) fail "reviewer did not run inside the packet";; esac
  grep -qx 'Read,Grep,Glob' "$FAKE_LOG.argv" || fail "tools not limited to Read,Grep,Glob"
  grep -qx -- '--setting-sources' "$FAKE_LOG.argv" || fail "--setting-sources missing"
  grep -qx -- '--no-session-persistence' "$FAKE_LOG.argv" || fail "--no-session-persistence missing"
  grep -qx 'opus' "$FAKE_LOG.argv" || fail "--model not passed through"
  [ ! -d "$TR/packet/tree" ] || fail "trial tree left on disk"
  # contaminated trial: same verdict, but the reviewer read outside the packet
  FAKE_READ=/etc/hosts bash "$S" run "$TMP/case.json" "$TMP/out2" --model opus >/dev/null || fail "contaminated run exited non-zero"
  TR2=$(ls -d "$TMP"/out2/toy/trial-* | head -1)
  [ "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["status"])' "$TR2/trial.json")" = contaminated ] || fail "outside read not marked contaminated"
  [ ! -e "$TR2/score.json" ] || fail "contaminated trial was scored"
  bash "$S" summary "$TMP/out" | grep -q '1/1 found' || fail "summary does not report 1/1 found"
  echo PASS
expected: exit 0 and prints PASS — with a fake CLAUDE_BIN, run spawns the reviewer with its cwd inside the trial packet and argv carrying Read,Grep,Glob, --setting-sources, --no-session-persistence and the chosen model; a trial whose reviewer reads only inside the packet is status scored with the expected finding found as a blocker, its exported tree removed; the same verdict with a read of /etc/hosts is status contaminated and has no score.json; summary reports 1/1 found.
phase: #161 · reference replay
owner: scripts/reference-replay.sh run, summary
