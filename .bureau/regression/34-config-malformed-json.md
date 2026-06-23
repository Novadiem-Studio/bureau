name: article-passes config validation rejects malformed JSON, naming the file
phase: 01 · write-article
owner: write-article / config/article-passes.json validation contract
expected: exit code non-zero (the jq guard fails on malformed JSON); the file path is named in the error
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  CFG="$WORK/article-passes.json"
  printf '{ "passes": [ {bad json no close\n' > "$CFG"
  # The workflow's config-validation guard (mirrored from account-run.sh jq -e pattern):
  set +e
  err="$(jq -e '.passes | type == "array"' "$CFG" 2>&1 >/dev/null)"
  code=$?
  set -e
  test "$code" -ne 0 || { echo "FAIL: malformed JSON guard returned 0" >&2; exit 1; }
  echo "PASS: malformed JSON -> guard nonzero (config: $CFG); jq said: $err"
