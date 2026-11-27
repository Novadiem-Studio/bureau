name: reference-replay build — exact-hash blind packet; refuses diff mismatch (3), leak (4), changed extra file (5), missing prompt (2)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  S="$ROOT/scripts/reference-replay.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  R="$TMP/repo"; mkdir -p "$R/docs"; git init -q "$R"
  git -C "$R" config user.email fixture@example.invalid; git -C "$R" config user.name fixture
  printf 'DIFFONLY_REMOVED_LINE = 1\ndef ok():\n    return 1\n' > "$R/app.py"
  printf '# Prompt 01\nAdd charge(); send credentials over HTTPS only.\n' > "$R/docs/01-prompt.md"
  git -C "$R" add -A; git -C "$R" commit -qm base; B=$(git -C "$R" rev-parse HEAD)
  printf 'def ok():\n    return 1\ndef charge(url, password):\n    return post(url, password)\n' > "$R/app.py"
  git -C "$R" commit -qam target; T=$(git -C "$R" rev-parse HEAD)
  D=$(git -C "$R" diff "$B" "$T" | python3 -c 'import hashlib,sys;print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')
  printf 'pinned note\n' > "$TMP/extra.md"
  X=$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$TMP/extra.md")
  mkcase() { # out diff_sha leak extra_sha prompt
    python3 - "$@" "$R" "$B" "$T" "$TMP/extra.md" <<'PY'
  import json, sys
  out, dsha, leak, xsha, prompt, repo, base, target, extra = sys.argv[1:]
  json.dump({"id": "toy-case", "kind": "known-miss", "review_mode": "build-diff",
             "target_repo": repo, "base_sha": base, "target_sha": target, "diff_sha": dsha,
             "prompt_paths": [prompt],
             "extra_files": [{"from": extra, "to": "notes/extra.md", "sha256": xsha}],
             "leak_patterns": [leak],
             "expected": [{"id": "e1", "anchor": "app.py", "pattern": "https",
                           "summary": "XYZZY-EXPECTED plain-http credentials"}],
             "notes": "XYZZY-EXPECTED answer text"}, open(out, "w"))
  PY
  }
  fail() { echo "FAIL: $1"; exit 1; }
  # happy path
  mkcase "$TMP/ok.json" "$D" "validate_https_url" "$X" docs/01-prompt.md
  P="$TMP/p-ok"; bash "$S" build "$TMP/ok.json" "$P" >/dev/null || fail "happy build exited non-zero"
  [ -f "$P/tree/app.py" ] && [ -f "$P/tree/docs/01-prompt.md" ] || fail "tree not exported"
  [ -z "$(find "$P" -name .git)" ] || fail "packet contains a .git"
  [ "$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$P/review.diff")" = "$D" ] || fail "review.diff is not the reviewed diff"
  [ -f "$P/persona/critic.md" ] && [ -f "$P/persona/build-diff.md" ] || fail "persona not staged"
  [ -f "$P/extra/notes/extra.md" ] || fail "pinned extra file not staged"
  grep -q "$T" "$P/BRIEF.md" || fail "BRIEF does not name the target commit"
  ! grep -rq 'XYZZY-EXPECTED' "$P" || fail "expected-finding text leaked into the packet"
  # refusals
  rc_of() { set +e; bash "$S" build "$1" "$2" >/dev/null 2>&1; r=$?; set -e; echo "$r"; }
  mkcase "$TMP/badsha.json" "0000000000000000000000000000000000000000000000000000000000000000" "validate_https_url" "$X" docs/01-prompt.md
  [ "$(rc_of "$TMP/badsha.json" "$TMP/p-badsha")" = 3 ] || fail "diff_sha mismatch did not exit 3"
  mkcase "$TMP/leak.json" "$D" "def charge" "$X" docs/01-prompt.md
  [ "$(rc_of "$TMP/leak.json" "$TMP/p-leak")" = 4 ] || fail "leak pattern in packet did not exit 4"
  [ ! -e "$TMP/p-leak" ] || fail "leaky packet was left on disk"
  ! grep -rq DIFFONLY_REMOVED_LINE "$P/tree" || fail "fixture setup: the diff-only string is in the tree"
  mkcase "$TMP/leakdiff.json" "$D" "DIFFONLY_REMOVED_LINE" "$X" docs/01-prompt.md
  [ "$(rc_of "$TMP/leakdiff.json" "$TMP/p-leakdiff")" = 4 ] || fail "leak pattern only in review.diff did not exit 4"
  mkcase "$TMP/extra.json" "$D" "validate_https_url" "1111111111111111111111111111111111111111111111111111111111111111" docs/01-prompt.md
  [ "$(rc_of "$TMP/extra.json" "$TMP/p-extra")" = 5 ] || fail "changed extra file did not exit 5"
  mkcase "$TMP/noprompt.json" "$D" "validate_https_url" "$X" docs/missing.md
  [ "$(rc_of "$TMP/noprompt.json" "$TMP/p-noprompt")" = 2 ] || fail "missing prompt path did not exit 2"
  echo PASS
expected: exit 0 and prints PASS — a correct case builds a packet holding the reviewed tree (no .git), the byte-exact reviewed diff, the persona and the pinned extra file, and none of the case's expected-finding text; a wrong diff_sha exits 3, a leak pattern present in the packet exits 4 and removes the packet (including a string found only in review.diff), a changed extra file exits 5, a prompt path absent from the tree exits 2.
phase: #161 · reference replay
owner: scripts/reference-replay.sh build
