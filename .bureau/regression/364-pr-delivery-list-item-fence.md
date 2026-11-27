name: pr-delivery.sh placeholder strip ends a fence opened in a list item where GitHub does: an opener after the item marker closes at its own item-indented closer, and a line indented less than the item ends the item and the fence, so the placeholder after it is linted
phase: bug-fix (run 20261126-placeholder-list-fence-152, issue #152 cases A and B)
owner: scripts/pr-delivery.sh (strip_code_spans, used by cmd_ready's placeholder lint)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  PATH=/usr/bin:/bin:$PATH
  T=$(mktemp -d)
  trap 'rm -rf "$T"' EXIT INT TERM
  # The exact function cmd_ready calls, extracted from the script.
  eval "$(sed -n '/^strip_code_spans() {/,/^}/p' "$ROOT/scripts/pr-delivery.sh")"
  command -v strip_code_spans >/dev/null 2>&1 || { echo "FAIL: strip_code_spans not found"; exit 1; }
  # Every row runs; a failed row is reported and the fixture fails at the end.
  bad=0
  strip() { strip_code_spans "$T/in.md" > "$T/out" || { echo "FAIL: $1: strip errored"; exit 1; }; }
  visible() { strip "$1"; grep -Fq "$2" "$T/out" || { echo "FAIL: $1: $2 was stripped"; bad=1; }; }
  hidden() { strip "$1"; if grep -Fq "$2" "$T/out"; then echo "FAIL: $1: $2 was not stripped"; bad=1; fi; }
  # Each file below ends with a later top-level fence of the same character, which every
  # under-lint row needs: with none, the fence the strip takes as open is unclosed and is
  # printed raw.

  # D1-D9: the opener shares its line with the item marker (issue #152 body). GitHub opens
  # the fence there and closes it at the item-indented closer, so <real> is plain text.
  printf -- '- ~~~\n  x\n  ~~~\n<real>\n\n~~~\ny\n~~~\n' > "$T/in.md"
  visible "D1 dash marker, tilde opener, closer at 2 (case A)" '<real>'
  printf -- '* ~~~\n  x\n  ~~~\n<real>\n\n~~~\ny\n~~~\n' > "$T/in.md"
  visible "D2 star marker" '<real>'
  printf -- '+ ~~~\n  x\n  ~~~\n<real>\n\n~~~\ny\n~~~\n' > "$T/in.md"
  visible "D3 plus marker" '<real>'
  printf -- '1. ~~~\n   x\n   ~~~\n<real>\n\n~~~\ny\n~~~\n' > "$T/in.md"
  visible "D4 1. marker, closer at 3" '<real>'
  printf -- '1) ~~~\n   x\n   ~~~\n<real>\n\n~~~\ny\n~~~\n' > "$T/in.md"
  visible "D5 1) marker, closer at 3" '<real>'
  printf -- '- ```\n  x\n  ```\n<real>\n\n```\ny\n```\n' > "$T/in.md"
  visible "D6 dash marker, backtick opener" '<real>'
  printf -- '1. ```\n   x\n   ```\n<real>\n\n```\ny\n```\n' > "$T/in.md"
  visible "D6 1. marker, backtick opener" '<real>'
  printf -- '- ~~~sh\n  x\n  ~~~\n<real>\n\n~~~\ny\n~~~\n' > "$T/in.md"
  visible "D7 opener with an info string" '<real>'
  printf -- '- ~~~\n  x\n   ~~~\n<real>\n\n~~~\ny\n~~~\n' > "$T/in.md"
  visible "D8 closer at 3, one column past the content indent" '<real>'
  # D9: nested markers; the 2-column ~~~ ends the inner item (and its fence) and opens a
  # fence in the outer item, and <real> ends that item.
  printf -- '- - ~~~\n    x\n  ~~~\n<real>\n\n~~~\ny\n~~~\n' > "$T/in.md"
  visible "D9 nested marker opener, closer at the outer item" '<real>'
  # D10-D13: the fence opens on its own line inside the item (issue #152 comment 1). A
  # line indented less than the item ends the item, and GitHub closes the fence there.
  printf 'text\n\n- item\n\n  ```\n  code\n\nreal placeholder <fill me>\n```\n\nafter\n' > "$T/in.md"
  visible "D10 item ended by an unindented line, backtick (comment 1)" '<fill me>'
  printf -- '- item\n\n  ~~~\n  x\n\n<real>\n\n~~~\ny\n~~~\n' > "$T/in.md"
  visible "D11 item ended by an unindented line, tilde" '<real>'
  printf -- '1. item\n\n   ~~~\n   x\n2. <real>\n\n~~~\ny\n~~~\n' > "$T/in.md"
  visible "D12 item ended by the next marker" '<real>'
  printf -- '- item\n\n  ~~~\n  x\n# h\n<real>\n\n~~~\ny\n~~~\n' > "$T/in.md"
  visible "D13 item ended by a heading" '<real>'
  # D14: D1 with CRLF line ends.
  printf -- '- ~~~\r\n  x\r\n  ~~~\r\n<real>\r\n\r\n~~~\r\ny\r\n~~~\r\n' > "$T/in.md"
  visible "D14 CRLF marker opener" '<real>'

  # Pins. P1: a 4-column fence in an item (issue #152 comment 2). GitHub shows <k> as code;
  # it stays linted (owner decision Nov 26 2026: no narrowing). Over-lint pin, fail-safe.
  printf -- '- Example:\n\n    ```sh\n    echo <k>\n    ```\n' > "$T/in.md"
  visible "P1 4-column fence in an item (over-lint)" '<k>'
  # P2, P3: fence bodies GitHub shows as code stay hidden.
  printf 'text\n\n```\n<k>\n```\n\nafter\n' > "$T/in.md"
  hidden "P2 top-level fence body" '<k>'
  printf -- '- item\n\n  ~~~\n  <k>\n  ~~~\n\nafter\n' > "$T/in.md"
  hidden "P3 item fence on its own line, body" '<k>'
  printf -- '1. step\n\n   ```sh\n   cmd <k>\n   ```\n2. next\n' > "$T/in.md"
  hidden "P3 ordered item fence, body" '<k>'
  # P4: ambiguous (4+ column) closers stay linted.
  printf -- '-   ~~~\n    x\n    ~~~\n<real>\n\n~~~\ny\n~~~\n' > "$T/in.md"
  visible "P4 three spaces after the marker, closer at 4" '<real>'
  printf -- '1.   ~~~\n     x\n     ~~~\n<real>\n\n~~~\ny\n~~~\n' > "$T/in.md"
  visible "P4 1. and three spaces, closer at 5" '<real>'
  printf -- '10. ~~~\n    x\n    ~~~\n<real>\n\n~~~\ny\n~~~\n' > "$T/in.md"
  visible "P4 10. marker, closer at 4" '<real>'
  printf -- '- ~~~\n  x\n    ~~~\n<real>\n\n~~~\ny\n~~~\n' > "$T/in.md"
  visible "P4 closer at 4" '<real>'
  printf -- '- - ~~~\n    x\n    ~~~\n<real>\n\n~~~\ny\n~~~\n' > "$T/in.md"
  visible "P4 nested marker opener, closer at 4" '<real>'
  # P5: no later fence, or a later fence of the other character, stays linted.
  printf -- '- item\n\n  ~~~\n  x\n\n<real>\n' > "$T/in.md"
  visible "P5 item fence, no later fence" '<real>'
  printf -- '- ~~~\n  x\n  ~~~\n<real>\n\n```\ny\n```\n' > "$T/in.md"
  visible "P5 marker opener, later fence of the other character" '<real>'
  # P6: the item ends before its closer (closer at 0 or 1, or at 2 after a 4-column
  # content indent), so GitHub closes the fence at the item end and that line opens a new
  # top-level fence holding <real>. Taking the line as the closer instead would show it.
  printf -- '- ~~~\n  x\n~~~\n<real>\n\n~~~\ny\n~~~\n' > "$T/in.md"
  hidden "P6 marker opener, line at 0 after the item" '<real>'
  printf -- '- ~~~\n  x\n ~~~\n<real>\n\n~~~\ny\n~~~\n' > "$T/in.md"
  hidden "P6 marker opener, line at 1 after the item" '<real>'
  printf -- '-   ~~~\n    x\n  ~~~\n<real>\n\n~~~\ny\n~~~\n' > "$T/in.md"
  hidden "P6 content indent 4, line at 2 after the item" '<real>'
  [ "$bad" = 0 ] || exit 1
  echo PASS
expected: exit 0; stdout "PASS". A fence opened in a list item ends where GitHub ends it. An opener on the marker line (dash, star, plus, 1. and 1) markers, backtick or tilde, with an info string, nested markers, CRLF) closes at a closer up to three columns past the item's content indent, so the placeholder after it is linted (D1-D9, D14). A non-blank line indented less than the item ends the item and the fence, so the placeholder on it or after it is linted (D10 issue comment 1, D11 tilde, D12 the next marker, D13 a heading). Pins: a 4-column fence in an item stays linted (P1, issue comment 2, owner's no-narrowing decision); fence bodies GitHub shows as code stay hidden (P2 top level, P3 own-line item fences); ambiguous 4+ column closers and files with no later same-character fence stay linted (P4, P5); a fence line indented less than the item is an item end and a new top-level opener, not a closer, so the fence it opens hides <real> as GitHub does (P6). All D rows are red on ecfca8f. Mutations (on copies of scripts/pr-delivery.sh, every row run): drop the list pass and D1-D14 fail; stop consuming item markers and D1-D9 and D14 fail; stop ending a fence at the item end and D10-D13 fail; make the list pass print a top-level fence body and P2 fails.
