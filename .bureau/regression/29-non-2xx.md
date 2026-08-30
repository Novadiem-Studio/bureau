name: model-pass.sh exits 2 on a non-2xx provider response and leaves the out-file unwritten
phase: 01 · write-article
owner: write-article / scripts/model-pass.sh
expected: exit code 2, AND the out-file is NOT created (prior draft survives)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  SCRIPT="$ROOT/scripts/model-pass.sh"
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  # Fake keystore so the script reaches the POST stage offline.
  mkdir -p "$WORK/home/Documents/novadiem/keys/novadiem"
  printf 'OPENROUTER_API_KEY=sk-test-not-real\n' > "$WORK/home/Documents/novadiem/keys/novadiem/openrouter.env"
  # Mock curl: emit a body + a 502 status on a trailing line (mirrors curl -w '\n%{http_code}').
  # The body deliberately carries NO `.error` key, so the ONLY guard that can produce exit 2
  # here is the HTTP-2xx status check itself (this keeps the mutation test honest — break the
  # status check and the fixture must flip, not get rescued by the .error check).
  mkdir -p "$WORK/bin"
  cat > "$WORK/bin/curl" <<'MOCK'
  #!/usr/bin/env bash
  printf '%s\n%s' '{"message":"upstream gateway timeout"}' '502'
  MOCK
  chmod +x "$WORK/bin/curl"
  printf 'This is a draft long enough to be non-empty and clear the input checks.\n' > "$WORK/draft.md"
  printf 'Improve this draft.\n' > "$WORK/instr.md"
  OUT="$WORK/out.md"
  set +e
  OPENROUTER_KEYSTORE="$WORK/home/Documents/novadiem/keys/novadiem/openrouter.env" HOME="$WORK/home" PATH="$WORK/bin:$PATH" bash "$SCRIPT" openrouter:x-ai/grok-4.3 "$WORK/draft.md" "$WORK/instr.md" "$OUT"
  code=$?
  set -e
  test "$code" -eq 2 || { echo "FAIL: expected exit 2, got $code" >&2; exit 1; }
  test ! -f "$OUT" || { echo "FAIL: out-file was written on non-2xx failure" >&2; exit 1; }
  echo "PASS: non-2xx -> exit 2, out-file untouched"
