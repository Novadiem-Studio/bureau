name: model-pass.sh exits 4 when the keystore key is absent
phase: 01 · write-article
owner: write-article / scripts/model-pass.sh
expected: exit code 4, AND the out-file is NOT created
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  SCRIPT="$ROOT/scripts/model-pass.sh"
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  # A fake HOME with NO openrouter.env — the keystore key is therefore absent.
  mkdir -p "$WORK/home"
  printf 'This is a draft long enough to be non-empty and clear the input checks.\n' > "$WORK/draft.md"
  printf 'Improve this draft.\n' > "$WORK/instr.md"
  OUT="$WORK/out.md"
  set +e
  HOME="$WORK/home" bash "$SCRIPT" openrouter:x-ai/grok-4.3 "$WORK/draft.md" "$WORK/instr.md" "$OUT"
  code=$?
  set -e
  test "$code" -eq 4 || { echo "FAIL: expected exit 4, got $code" >&2; exit 1; }
  test ! -f "$OUT" || { echo "FAIL: out-file was written on missing-key failure" >&2; exit 1; }
  echo "PASS: missing key -> exit 4, out-file untouched"
