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
  printf '%s\n' "${CLAUDE_CODE_DISABLE_AUTO_MEMORY:-unset}" > "$FAKE_LOG.mem"
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then echo yes; else echo no; fi > "$FAKE_LOG.git"
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
  # Results go inside a git repo, the way the private cases repo keeps them.
  git init -q "$TMP/results"
  # clean trial
  FAKE_READ=review.diff bash "$S" run "$TMP/case.json" "$TMP/results/out" --model opus >/dev/null || fail "clean run exited non-zero"
  TR=$(ls -d "$TMP"/results/out/toy/trial-* | head -1)
  [ "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["status"])' "$TR/trial.json")" = scored ] || fail "clean trial not scored"
  [ "$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["pass"],d["all_as_blocker"])' "$TR/score.json")" = "True True" ] || fail "clean trial score wrong"
  case "$(cat "$FAKE_LOG.cwd")" in */packet) ;; *) fail "reviewer did not run inside the packet";; esac
  grep -qx 'Read,Grep,Glob' "$FAKE_LOG.argv" || fail "tools not limited to Read,Grep,Glob"
  grep -qx -- '--setting-sources' "$FAKE_LOG.argv" || fail "--setting-sources missing"
  grep -qx -- '--no-session-persistence' "$FAKE_LOG.argv" || fail "--no-session-persistence missing"
  grep -qx 'opus' "$FAKE_LOG.argv" || fail "--model not passed through"
  [ "$(cat "$FAKE_LOG.git")" = no ] || fail "reviewer ran inside a git work tree (auto-memory would be injected)"
  [ "$(cat "$FAKE_LOG.mem")" = 1 ] || fail "CLAUDE_CODE_DISABLE_AUTO_MEMORY not set for the reviewer"
  python3 -c 'import sys
  a = open(sys.argv[1]).read().split("\n")
  def after(flag):
      return a[a.index(flag) + 1] if flag in a else None
  assert after("--setting-sources") == "", "setting-sources not empty"
  assert after("--output-format") == "stream-json", "output-format"
  assert after("--add-dir") and after("--add-dir").endswith("/packet"), "add-dir"
  assert "--json-schema" in a and "Challenger verdict" in "\n".join(a), "json-schema"
  assert after("--system-prompt") and "Challenger" in after("--system-prompt"), "system-prompt"' "$FAKE_LOG.argv" || fail "reviewer sandbox flags wrong"
  [ -f "$TR/packet/BRIEF.md" ] && [ -f "$TR/packet/review.diff" ] || fail "trial packet (minus tree) not kept"
  python3 -c 'import json,sys;m=json.load(open(sys.argv[1]));assert m["effort"]=="cli-default" and "cli_version" in m' "$TR/trial.json" || fail "effort and CLI version not recorded"
  [ ! -d "$TR/packet/tree" ] || fail "trial tree left on disk"
  # contaminated trial: same verdict, but the reviewer read outside the packet
  FAKE_READ=/etc/hosts bash "$S" run "$TMP/case.json" "$TMP/results/out2" --model opus >/dev/null || fail "contaminated run exited non-zero"
  TR2=$(ls -d "$TMP"/results/out2/toy/trial-* | head -1)
  [ "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["status"])' "$TR2/trial.json")" = contaminated ] || fail "outside read not marked contaminated"
  [ ! -e "$TR2/score.json" ] || fail "contaminated trial was scored"
  bash "$S" summary "$TMP/results/out" | grep -q '1/1 found' || fail "summary does not report 1/1 found"
  echo PASS
expected: exit 0 and prints PASS — with a fake CLAUDE_BIN and the out-dir inside a git repo, run spawns the reviewer with its cwd in a packet outside every git work tree, CLAUDE_CODE_DISABLE_AUTO_MEMORY=1, and argv carrying Read,Grep,Glob, an empty --setting-sources, --no-session-persistence, stream-json output, --add-dir on the packet, the Challenger verdict schema, the system prompt and the chosen model; the kept trial packet holds BRIEF.md and review.diff, and trial.json records effort and CLI version; a trial whose reviewer reads only inside the packet is status scored with the expected finding found as a blocker, its exported tree removed; the same verdict with a read of /etc/hosts is status contaminated and has no score.json; summary reports 1/1 found.
phase: #161 · reference replay
owner: scripts/reference-replay.sh run, summary
