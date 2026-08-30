name: model-pass.sh writes the candidate and exits 0 when all integrity checks pass (offline mock)
phase: 01 · write-article
owner: write-article / scripts/model-pass.sh
expected: exit code 0, the out-file IS created with the model's content, and the --run-dir log gets an [EXTERNAL-ACTION] status=ok line
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  SCRIPT="$ROOT/scripts/model-pass.sh"
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  mkdir -p "$WORK/home/Documents/novadiem/keys/novadiem"
  printf 'OPENROUTER_API_KEY=sk-test-not-real\n' > "$WORK/home/Documents/novadiem/keys/novadiem/openrouter.env"
  # Mock curl: 200, finish_reason stop, content sized within the 50%-300% band of the draft.
  mkdir -p "$WORK/bin"
  cat > "$WORK/bin/curl" <<'MOCK'
  #!/usr/bin/env bash
  body='{"choices":[{"finish_reason":"stop","message":{"content":"This is the improved draft. It is clearer and tighter while keeping the original argument and voice intact."}}]}'
  printf '%s\n%s' "$body" '200'
  MOCK
  chmod +x "$WORK/bin/curl"
  printf 'This is a draft long enough to be non-empty and clear the input checks.\n' > "$WORK/draft.md"
  printf 'Improve this draft.\n' > "$WORK/instr.md"
  OUT="$WORK/out.md"
  RUN="$WORK/run"; mkdir -p "$RUN"; : > "$RUN/log.md"
  set +e
  OPENROUTER_KEYSTORE="$WORK/home/Documents/novadiem/keys/novadiem/openrouter.env" HOME="$WORK/home" PATH="$WORK/bin:$PATH" bash "$SCRIPT" openrouter:x-ai/grok-4.3 "$WORK/draft.md" "$WORK/instr.md" "$OUT" --run-dir "$RUN"
  code=$?
  set -e
  test "$code" -eq 0 || { echo "FAIL: expected exit 0, got $code" >&2; exit 1; }
  test -s "$OUT" || { echo "FAIL: out-file not written or empty on success" >&2; exit 1; }
  grep -q 'improved draft' "$OUT" || { echo "FAIL: out-file does not contain the model content" >&2; exit 1; }
  grep -q '\[EXTERNAL-ACTION\] model-pass: .*status=ok exit=0' "$RUN/log.md" || { echo "FAIL: no ok external-action log line" >&2; exit 1; }
  # No leftover temp file.
  test -z "$(find "$WORK" -name 'out.md.tmp.*')" || { echo "FAIL: temp file left behind" >&2; exit 1; }
  echo "PASS: happy path -> exit 0, candidate written, ok log line, no temp leftover"
