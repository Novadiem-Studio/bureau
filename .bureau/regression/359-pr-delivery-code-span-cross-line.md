name: pr-delivery.sh placeholder strip removes a code span that wraps one line break, but never across a blank line, fence, block start, second break, indented code line, table row or HTML block
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
  # B1: an indented code line (4+ columns) stands alone; it never joins the next line.
  printf 'intro\n\n    cmd `\nsee <real> ` tail\n' > "$T/in.md"
  visible "B1 indented code line" '<real>'
  # T1: table rows without a leading pipe stand alone, so a span cannot pair across rows.
  printf 'a | b\n--- | ---\nx ` <real> | y\nz ` | w\n' > "$T/in.md"
  visible "T1 table rows without a leading pipe" '<real>'
  # T2: a pipe-less line after a table row is still a row (GFM) and stands alone too.
  printf 'a | b\n--- | ---\nx ` <real>\nz ` w\n' > "$T/in.md"
  visible "T2 pipe-less row after a table" '<real>'
  # T3: a span inside one table row is still stripped.
  printf 'a | b\n--- | ---\n`x <k>` | y\n' > "$T/in.md"
  hidden "T3 span inside a row" '<k>'
  # T4: a blank line ends the table, so a wrapped span after it is stripped again.
  printf 'a | b\n--- | ---\nx | y\n\nsee `foo <k>\nbar` end\n' > "$T/in.md"
  hidden "T4 wrapped span after a table" '<k>'
  # H1: a line starting with < starts an HTML block; a span never pairs into it.
  printf 'text `\n<div> <real> ` tail\n' > "$T/in.md"
  visible "H1 HTML block start" '<real>'
  # H2: lines inside an HTML block (up to the blank line) never pair a span either.
  printf '<div>\nfoo `a\nb <real> ` c\n</div>\n' > "$T/in.md"
  visible "H2 inside an HTML block" '<real>'
  echo PASS
expected: exit 0; stdout "PASS". strip_code_spans removes a closed inline code span that wraps a single line break (P1) and keeps text after it (P2), but a span does not cross a blank line (R1), a second line break (R2), a fence (R3), a new list item (R4), a block quote line (R5) or out of a heading (R6); an unclosed span at end of file is printed whole (R7), and an escaped backtick opens nothing (R8), so each <real> placeholder stays visible to cmd_ready's lint. Mutation: make strip_inline stop at the first newline and P1 fails; remove the second-newline limit and R2 fails; drop the flush at a blank line and R1 fails, before a fence and R3 fails, before a list or quote line and R4 fails; let a heading join the next line and R6 fails. CodeRabbit pass: an indented code line never joins (B1), table rows with or without a leading pipe never join, nor a pipe-less row after one, until a blank line (T1, T2), a span inside one row still strips (T3) and a wrapped span after the table's blank line strips again (T4), and an HTML block start and its lines up to a blank line never pair a span (H1, H2). Mutation: drop the indented-code rule and B1 fails; stop treating a pipe line as a row and T1 fails; make table mode not sticky and T2 fails; stop a blank line clearing it and T4 fails; stop treating a leading < as an HTML start and H1 fails; make HTML mode not sticky and H2 fails.
