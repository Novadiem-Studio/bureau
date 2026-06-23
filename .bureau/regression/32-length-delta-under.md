name: model-pass.sh exits 3 when output is under 50% of the input byte count
phase: 01 · write-article
owner: write-article / scripts/model-pass.sh
expected: exit code 3, AND the out-file is NOT created
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  SCRIPT="$ROOT/scripts/model-pass.sh"
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  mkdir -p "$WORK/home/Documents/novadiem/keys/novadiem"
  printf 'OPENROUTER_API_KEY=sk-test-not-real\n' > "$WORK/home/Documents/novadiem/keys/novadiem/openrouter.env"
  # Mock curl: 200, finish_reason stop, but content is tiny relative to the draft.
  mkdir -p "$WORK/bin"
  cat > "$WORK/bin/curl" <<'MOCK'
  #!/usr/bin/env bash
  body='{"choices":[{"finish_reason":"stop","message":{"content":"Too short."}}]}'
  printf '%s\n%s' "$body" '200'
  MOCK
  chmod +x "$WORK/bin/curl"
  # ~71-byte draft; 50% floor is ~35 bytes; "Too short." (10 bytes) is well under.
  printf 'This is a draft long enough to be non-empty and clear the input checks.\n' > "$WORK/draft.md"
  printf 'Improve this draft.\n' > "$WORK/instr.md"
  OUT="$WORK/out.md"
  set +e
  HOME="$WORK/home" PATH="$WORK/bin:$PATH" bash "$SCRIPT" openrouter:x-ai/grok-4.3 "$WORK/draft.md" "$WORK/instr.md" "$OUT"
  code=$?
  set -e
  test "$code" -eq 3 || { echo "FAIL: expected exit 3, got $code" >&2; exit 1; }
  test ! -f "$OUT" || { echo "FAIL: out-file was written despite under-length output" >&2; exit 1; }
  echo "PASS: length-delta under 50% -> exit 3, out-file untouched"
