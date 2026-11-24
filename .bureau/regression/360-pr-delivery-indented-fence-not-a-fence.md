name: pr-delivery.sh placeholder strip opens a fence only at 3 columns or less; a ``` line at 4+ columns opens nothing, a closer closes at any indent, the body before a 4+ column closer is linted, and after a 4+ column fence line no fence opens
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
  # I4: a closer indented four spaces is ambiguous (top level: code; in a list item: a
  # closer). It closes the fence, so <x> is linted although GitHub shows it as code.
  # Over-lint pin, fail-safe.
  printf '```\ncode\n    ```\n<x> still code\n```\n' > "$T/in.md"
  visible "I4 four-space closer (over-lint)" '<x>'
  # L1: in a list item a closer two columns in from the item (four absolute) closes the
  # fence on GitHub, so the placeholder after it is plain text.
  printf 'text\n\n- item\n\n  ```\n  code\n    ```\n\nreal placeholder <fill me>\n\n```sh\ncode\n```\n' > "$T/in.md"
  visible "L1 list-item closer at four columns" '<fill me>'
  # R1: at top level that closer is code on GitHub, so the next ``` closes the fence and
  # the placeholder after it is plain text. After an ambiguous closer no fence reopens.
  printf '```\ncode\n    ```\nplain\n```\nreal placeholder <fill me>\n```\nmore\n```\n' > "$T/in.md"
  visible "R1 no reopen after four-space closer" '<fill me>'
  # R2: the same with a tab-indented ~~~ closer and a longer ~~~~ fence.
  printf '~~~~\ncode\n\t~~~~~\nplain\n~~~~\nreal placeholder <fill me>\n~~~~\nmore\n~~~~\n' > "$T/in.md"
  visible "R2 no reopen after tab ~~~ closer" '<fill me>'
  # O1: in a list item an opener two columns in from the item (four absolute) opens a
  # fence on GitHub, closed by the item-indented ``` below it; the placeholder after
  # that is plain text. A 4+ column opener opens nothing and no fence opens after it.
  printf 'text\n\n- item\n\n    ```\n    code\n  ```\nreal placeholder <fill me>\n```\nmore\n```\n' > "$T/in.md"
  visible "O1 list-item opener at four columns" '<fill me>'
  # O2: the same in an ordered item, opener at four columns, closer at three.
  printf 'text\n\n1. step\n\n    ```\n    code\n   ```\nreal placeholder <fill me>\n```\nmore\n```\n' > "$T/in.md"
  visible "O2 ordered-item opener at four columns" '<fill me>'
  # E1: the list item ends inside the fence (an unindented line), so GitHub closes the
  # fence there and shows the placeholder as a paragraph; the 4-space ``` after it is
  # paragraph text. The body before an ambiguous closer is linted, not dropped.
  printf 'text\n\n- item\n\n  ```\n  code\n\nreal placeholder <fill me>\n    ```\n\nafter\n' > "$T/in.md"
  visible "E1 list ends before ambiguous closer" '<fill me>'
  # A1: while the item holds, the body before the ambiguous closer is code on GitHub, but
  # it is linted for E1's sake. Over-lint pin, fail-safe.
  printf 'text\n\n- item\n\n  ```\n  <k>\n    ```\n\nafter\n' > "$T/in.md"
  visible "A1 list fence body (over-lint)" '<k>'
  # C1: three spaces of indent still open and close a fence.
  printf 'text\n\n   ```\n<k>\n   ```\n\nafter\n' > "$T/in.md"
  hidden "C1 three-space fence" '<k>'
  echo PASS
expected: exit 0; stdout "PASS". A ``` line indented four or more columns (four spaces I1, a tab I2, two spaces and a tab I3) opens no fence, so a later placeholder before the next real fence stays visible to the lint. A closer at any indent closes an open fence. A fence line at four or more columns is ambiguous (a list item's fence line on GitHub, L1 closer, O1 and O2 openers; code at top level, R1), so after it no fence opens and every later line is linted (L1, O1, O2, R1, R2 visible; I4 is an over-lint pin). The body of a fence closed by an ambiguous closer is linted, not dropped, because a list item can end inside it (E1 visible; A1 is an over-lint pin). A fence indented three spaces still opens and closes (C1). Mutation: drop the `col <= 3` test on the opener (open at any indent) and I1-I3 fail; restore `col <= 3` on the closer and I4 and L1 fail; drop the `!amb` test on the opener and R1, R2, O1 and O2 fail; stop a 4+ column opener setting amb and O1 and O2 fail; drop the body at an ambiguous closer again and E1 and A1 fail.
