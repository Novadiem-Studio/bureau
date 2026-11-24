name: pr-delivery.sh placeholder strip treats a ``` line indented 4+ columns as text, not a fence opener or closer
phase: bug-fix (run 20261124-gate-edges-149, issue #149 item 3)
owner: scripts/pr-delivery.sh (strip_code_spans, used by cmd_ready's placeholder lint)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  PATH=/usr/bin:/bin:$PATH
  T=$(mktemp -d)
  trap 'rm -rf "$T"' EXIT INT TERM
  # The exact function cmd_ready calls, extracted from the script.
  eval "$(sed -n '/^strip_code_spans() {/,/^}/p' "$ROOT/scripts/pr-delivery.sh")"
  command -v strip_code_spans >/dev/null 2>&1 || { echo "FAIL: strip_code_spans not found"; exit 1; }
  strip() { strip_code_spans "$T/in.md" > "$T/out" || { echo "FAIL: $1: strip errored"; exit 1; }; }
  visible() { strip "$1"; grep -Fq "$2" "$T/out" || { echo "FAIL: $1: $2 was stripped"; cat "$T/out"; exit 1; }; }
  hidden() { strip "$1"; if grep -Fq "$2" "$T/out"; then echo "FAIL: $1: $2 was not stripped"; cat "$T/out"; exit 1; fi; }

  # I1: four spaces of indent make it indented code, so it opens no fence and the
  # placeholder before the next real fence is plain text.
  printf 'text\n\n    ```\n\nreal placeholder <fill me>\n\n```sh\ncode\n```\n' > "$T/in.md"
  visible "I1 four-space opener" '<fill me>'
  # I2: a leading tab is four columns.
  printf 'text\n\n\t```\n\nreal placeholder <fill me>\n\n```sh\ncode\n```\n' > "$T/in.md"
  visible "I2 tab opener" '<fill me>'
  # I3: two spaces and a tab reach column 4 too.
  printf 'text\n\n  \t```\n\nreal placeholder <fill me>\n\n```sh\ncode\n```\n' > "$T/in.md"
  visible "I3 spaces-then-tab opener" '<fill me>'
  # I4: a closer indented four spaces does not close an open fence, so what follows is
  # still code up to the real closer.
  printf '```\ncode\n    ```\n<x> still code\n```\n' > "$T/in.md"
  hidden "I4 four-space closer" '<x>'
  # C1: three spaces of indent still open and close a fence.
  printf 'text\n\n   ```\n<k>\n   ```\n\nafter\n' > "$T/in.md"
  hidden "C1 three-space fence" '<k>'
  echo PASS
expected: exit 0; stdout "PASS". A ``` line indented four or more columns (four spaces I1, a tab I2, two spaces and a tab I3) opens no fence, so a later placeholder before the next real fence stays visible to the lint; a ``` closer indented four spaces does not close an open fence (I4); a fence indented three spaces still opens and closes (C1). Mutation: drop the `col <= 3` test on the opener in strip_code_spans and I1-I3 fail; drop it on the closer and I4 fails.
