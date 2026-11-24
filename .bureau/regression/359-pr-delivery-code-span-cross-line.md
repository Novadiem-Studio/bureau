name: pr-delivery.sh placeholder strip removes a code span that wraps one line break, but never across a blank line, fence, block start or second break
phase: bug-fix (run 20261124-gate-edges-149, issue #149 item 1)
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

  # P1: a closed span that wraps one line break is code (the issue #149 case).
  printf 'see `foo <k>\nbar` for details\n' > "$T/in.md"
  hidden "P1 span across one line break" '<k>'
  # P2: text outside the wrapped span is still linted.
  printf 'see `foo <k>\nbar` then <real>\n' > "$T/in.md"
  visible "P2 text after a wrapped span" '<real>'
  # R1: a span never crosses a blank line (a paragraph break).
  printf 'see `foo <real>\n\nbar` x\n' > "$T/in.md"
  visible "R1 blank line" '<real>'
  # R2: a span crosses at most one line break.
  printf 'a `x <real>\nmiddle\nb` c\n' > "$T/in.md"
  visible "R2 second line break" '<real>'
  # R3: a fence line ends the paragraph, so a backtick after the fence closes nothing before it.
  printf 'a `x <real>\n~~~\ncode\n~~~\nb` c\n' > "$T/in.md"
  visible "R3 fence between" '<real>'
  # R4: a new list item starts a new block.
  printf -- '- ran `x <real>\n- then` y\n' > "$T/in.md"
  visible "R4 next list item" '<real>'
  # R5: a block quote line starts a new block.
  printf 'a `x <real>\n> b` c\n' > "$T/in.md"
  visible "R5 block quote" '<real>'
  # R6: a heading is one line; the next line cannot close a span opened in it.
  printf '# a `x <real>\nb` c\n' > "$T/in.md"
  visible "R6 heading" '<real>'
  # R7: an unclosed span in a multi-line paragraph at end of file is printed whole.
  printf 'line one\nRan `x <real>\n' > "$T/in.md"
  visible "R7 unclosed at EOF" '<real>'
  # R8: a backslash-escaped backtick opens no span, even with a backtick on the next line.
  printf 'Ran \\`<real>\nb` c\n' > "$T/in.md"
  visible "R8 escaped opener" '<real>'
  echo PASS
expected: exit 0; stdout "PASS". strip_code_spans removes a closed inline code span that wraps a single line break (P1) and keeps text after it (P2), but a span does not cross a blank line (R1), a second line break (R2), a fence (R3), a new list item (R4), a block quote line (R5) or out of a heading (R6); an unclosed span at end of file is printed whole (R7), and an escaped backtick opens nothing (R8), so each <real> placeholder stays visible to cmd_ready's lint. Mutation: make strip_inline stop at the first newline and P1 fails; remove the second-newline limit and R2 fails; drop the flush at a blank line and R1 fails, before a fence and R3 fails, before a list, quote or table line and R4 fails; let a heading join the next line and R6 fails.
