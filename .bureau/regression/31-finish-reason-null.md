name: model-pass.sh exits 3 when finish_reason is null or absent
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
  # Mock curl: a 200 response with NO finish_reason key (jq // "null" => "null"); must reject.
  mkdir -p "$WORK/bin"
  cat > "$WORK/bin/curl" <<'MOCK'
  #!/usr/bin/env bash
  body='{"choices":[{"message":{"content":"This improved draft is well sized but the provider omitted any finish_reason field."}}]}'
  printf '%s\n%s' "$body" '200'
  MOCK
  chmod +x "$WORK/bin/curl"
  printf 'This is a draft long enough to be non-empty and clear the input checks.\n' > "$WORK/draft.md"
  printf 'Improve this draft.\n' > "$WORK/instr.md"
  OUT="$WORK/out.md"
  set +e
  HOME="$WORK/home" PATH="$WORK/bin:$PATH" bash "$SCRIPT" openrouter:x-ai/grok-4.3 "$WORK/draft.md" "$WORK/instr.md" "$OUT"
  code=$?
  set -e
  test "$code" -eq 3 || { echo "FAIL: expected exit 3, got $code" >&2; exit 1; }
  test ! -f "$OUT" || { echo "FAIL: out-file was written despite absent finish_reason" >&2; exit 1; }
  echo "PASS: finish_reason null/absent -> exit 3, out-file untouched"
