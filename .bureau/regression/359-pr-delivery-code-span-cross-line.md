name: pr-delivery.sh placeholder strip never matches a code span across a line break (each line stripped on its own); a span that wraps a break stays visible as a fail-safe over-lint tracked in issue #153, no join can hide a placeholder, and a backtick left unmatched on one line keeps later lines of its paragraph linted raw
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

  # No span is matched across a line break: every line is stripped on its own, as on main
  # a2d4029, and later lines of a paragraph are also printed raw once one line leaves a
  # backtick unmatched (XF0 below). A positive below that says "over-lint, issue #153" pins a span CommonMark does
  # wrap (GitHub renders it as code) whose <k> stays visible, so the lint refuses it. That is
  # fail-safe and tracked in issue #153; every guard keeps a real <real> visible.
  # P1 (over-lint, issue #153): a closed span that wraps one line break is not stripped.
  printf 'see `foo <k>\nbar` for details\n' > "$T/in.md"
  visible "P1 over-lint: span across one line break" '<k>'
  # P2: text after a backtick that would close a wrapped span is still linted.
  printf 'see `foo <k>\nbar` then <real>\n' > "$T/in.md"
  visible "P2 text after a wrapped span" '<real>'
  # R1: a backtick never pairs across a blank line.
  printf 'see `foo <real>\n\nbar` x\n' > "$T/in.md"
  visible "R1 blank line" '<real>'
  # R2: nor across two line breaks.
  printf 'a `x <real>\nmiddle\nb` c\n' > "$T/in.md"
  visible "R2 second line break" '<real>'
  # R3: nor across a fence.
  printf 'a `x <real>\n~~~\ncode\n~~~\nb` c\n' > "$T/in.md"
  visible "R3 fence between" '<real>'
  # R4-R6: nor from a list item, block quote or heading line into the next line.
  printf -- '- ran `x <real>\n- then` y\n' > "$T/in.md"
  visible "R4 next list item" '<real>'
  printf 'a `x <real>\n> b` c\n' > "$T/in.md"
  visible "R5 block quote" '<real>'
  printf '# a `x <real>\nb` c\n' > "$T/in.md"
  visible "R6 heading" '<real>'
  # R7: an unclosed span in a multi-line paragraph at end of file is printed whole.
  printf 'line one\nRan `x <real>\n' > "$T/in.md"
  visible "R7 unclosed at EOF" '<real>'
  # R8: a backslash-escaped backtick opens no span, even with a backtick on the next line.
  printf 'Ran \\`<real>\nb` c\n' > "$T/in.md"
  visible "R8 escaped opener" '<real>'
  # B1: an indented code line (4+ columns) never pairs with the next line.
  printf 'intro\n\n    cmd `\nsee <real> ` tail\n' > "$T/in.md"
  visible "B1 indented code line" '<real>'
  # B2: indented code holding a lone backtick, then prose: the placeholder is not in a span.
  printf '    `example\n<real>`\n' > "$T/in.md"
  visible "B2 indented code then prose" '<real>'
  # T1, T2: table rows, with or without a pipe, never pair a backtick across rows.
  printf 'a | b\n--- | ---\nx ` <real> | y\nz ` | w\n' > "$T/in.md"
  visible "T1 table rows without a leading pipe" '<real>'
  printf 'a | b\n--- | ---\nx ` <real>\nz ` w\n' > "$T/in.md"
  visible "T2 pipe-less row after a table" '<real>'
  # T3: a span inside one table row is still stripped.
  printf 'a | b\n--- | ---\n`x <k>` | y\n' > "$T/in.md"
  hidden "T3 span inside a row" '<k>'
  # T4 (over-lint, issue #153): a wrapped span after a table, past a blank line, is not stripped.
  printf 'a | b\n--- | ---\nx | y\n\nsee `foo <k>\nbar` end\n' > "$T/in.md"
  visible "T4 over-lint: wrapped span after a table" '<k>'
  # H1, H2: a backtick never pairs into, or inside, an HTML block.
  printf 'text `\n<div> <real> ` tail\n' > "$T/in.md"
  visible "H1 HTML block start" '<real>'
  printf '<div>\nfoo `a\nb <real> ` c\n</div>\n' > "$T/in.md"
  visible "H2 inside an HTML block" '<real>'
  # L1 (over-lint, issue #153): a span wrapping onto a lazy indented continuation line is
  # not stripped, though CommonMark closes it there.
  printf 'see `foo <k>\n    bar` end\n' > "$T/in.md"
  visible "L1 over-lint: lazy indented continuation" '<k>'
  # G1, G1b: indented code after a bare list or quote marker never pairs with the next line.
  printf -- '-\n      cmd `\nsee <real> ` tail\n' > "$T/in.md"
  visible "G1 indented code after a bare list marker" '<real>'
  printf '>\n      cmd `\nsee <real> ` tail\n' > "$T/in.md"
  visible "G1b indented code after a bare quote marker" '<real>'
  # G2: nor does a nested list item.
  printf -- '- a `x <real>\n    - b` c\n' > "$T/in.md"
  visible "G2 indented nested list item" '<real>'
  printf -- '- parent\n  - ran `x <real>\n    - then` y\n' > "$T/in.md"
  visible "G2b nested list marker at four columns under a nested item" '<real>'
  # P3 (over-lint, issue #153): a span wrapping after a line holding a pipe is not stripped.
  printf 'ran `cat x <k> |\ngrep y` done\n' > "$T/in.md"
  visible "P3 over-lint: prose with a pipe" '<k>'
  # G3: a backtick opened before a table header never closes in it.
  printf 'see `x <real>\na ` | b\n--- | ---\n' > "$T/in.md"
  visible "G3 header split from the line before" '<real>'
  # G4: nor after a table inside a block quote.
  printf '> a | b\n> --- | ---\n> x | y\n> z ` | w\nnext <real> ` tail\n' > "$T/in.md"
  visible "G4 table in a block quote" '<real>'
  # G5-G8: rows under a table header, pipe or no pipe, hashes or a heading among them,
  # never pair a backtick.
  printf '| a |\n---\nx ` <real>\ny ` z\n' > "$T/in.md"
  visible "G5 pipe-less delimiter under a pipe header" '<real>'
  # T5 (over-lint, issue #153): a span wrapping after a table and a heading is not stripped.
  printf 'a | b\n--- | ---\nx | y\n# Next\nsee `foo <k>\nbar` end\n' > "$T/in.md"
  visible "T5 over-lint: heading after a table" '<k>'
  printf 'a | b\n--- | ---\n####### x\np ` <real>\nq ` r\n' > "$T/in.md"
  visible "G6 seven hashes stay a row" '<real>'
  printf 'a | b\n--- | ---\n#x\np ` <real>\nq ` r\n' > "$T/in.md"
  visible "G7 hash without a blank stays a row" '<real>'
  printf 'a | b\n--- | ---\n# h `x <real>\nb` c\n' > "$T/in.md"
  visible "G8 heading after a table stands alone" '<real>'
  # G10-G13: indented code after a setext underline, a thematic break, or a heading or
  # rule inside a list item never pairs with the next line.
  printf 'title\n---\n    cmd `\nsee <real> ` tail\n' > "$T/in.md"
  visible "G10 indented code after a setext underline" '<real>'
  printf 'para\n***\n    cmd `\nsee <real> ` tail\n' > "$T/in.md"
  visible "G11 indented code after a thematic break" '<real>'
  printf -- '- # h\n      cmd `\nsee <real> ` tail\n' > "$T/in.md"
  visible "G12 indented code after a list-item heading" '<real>'
  printf -- '- a\n    ***\n      cmd `\nsee <real> ` tail\n' > "$T/in.md"
  visible "G13 indented code after a list-item rule" '<real>'
  # G14, G15: table rows inside a list item never pair.
  printf -- '- x\n    a | b\n    --|--\n  p ` <real> | y\n  z ` | w\n' > "$T/in.md"
  visible "G14 indented table in a list item" '<real>'
  printf -- '- x\n    | a |\n    ---\n  p ` <real>\n  z ` w\n' > "$T/in.md"
  visible "G15 pipe-less delimiter under a solo pipe header" '<real>'
  # G16, G16b: CRLF line ends change nothing.
  printf 'a | b\r\n--- | ---\r\nx ` <real>\r\nz ` w\r\n' > "$T/in.md"
  visible "G16 CRLF table" '<real>'
  printf -- '-\r\n      cmd `\r\nsee <real> ` tail\r\n' > "$T/in.md"
  visible "G16b CRLF bare list marker" '<real>'
  # G9: lines of an HTML block never pair, a heading among them or not.
  printf '<div>\n# h\nfoo `a\nb <real> ` c\n</div>\n' > "$T/in.md"
  visible "G9 heading inside an HTML block" '<real>'
  # LM1-LM13: a backtick on a list marker or quote line never closes on the next line, and
  # the lines after it (LM5) never pair.
  printf -- '- # a `x <real>\nb` c\n' > "$T/in.md"
  visible "LM1 heading after a list marker" '<real>'
  printf -- '- ~~~ `x <real>\nb` c\n' > "$T/in.md"
  visible "LM2 tilde fence after a list marker" '<real>'
  printf -- '- ``` `x <real>\nb` c\n' > "$T/in.md"
  visible "LM3 backtick fence after a list marker" '<real>'
  printf -- '- <span> `x <real>\nb` c\n' > "$T/in.md"
  visible "LM4 HTML start after a list marker" '<real>'
  printf -- '- <div>\n  foo `a\n  b <real> ` c\n' > "$T/in.md"
  visible "LM5 HTML block after a list marker" '<real>'
  printf -- '- a | `x <real>\nb` c\n' > "$T/in.md"
  visible "LM6 pipe after a list marker" '<real>'
  printf -- '* # a `x <real>\nb` c\n' > "$T/in.md"
  visible "LM7 star marker" '<real>'
  printf -- '+ # a `x <real>\nb` c\n' > "$T/in.md"
  visible "LM8 plus marker" '<real>'
  printf -- '1. # a `x <real>\nb` c\n' > "$T/in.md"
  visible "LM9 dot-numbered marker" '<real>'
  printf -- '1) # a `x <real>\nb` c\n' > "$T/in.md"
  visible "LM10 paren-numbered marker" '<real>'
  printf -- '> - # a `x <real>\nb` c\n' > "$T/in.md"
  visible "LM11 quoted list marker" '<real>'
  printf -- '   - # a `x <real>\nb` c\n' > "$T/in.md"
  visible "LM12 list marker at 3 columns" '<real>'
  printf -- '> # a `x <real>\nb` c\n' > "$T/in.md"
  visible "LM13 heading in a block quote" '<real>'
  # LH1 (over-lint, issue #153): a span in a list item wrapping onto its continuation line
  # is not stripped.
  printf -- '- see `foo <k>\n  bar` end\n' > "$T/in.md"
  visible "LH1 over-lint: span in a list item" '<k>'
  # Q1, Q1b: indented code on a list marker line, plain or quoted, never pairs with the
  # next line (red on 1246656).
  printf -- '-     cmd `\nsee <real> ` tail\n' > "$T/in.md"
  visible "Q1 indented code after a list marker" '<real>'
  printf -- '> -     cmd `\n> see <real> ` tail\n' > "$T/in.md"
  visible "Q1b quoted indented code after a list marker" '<real>'
  # F1 (over-lint, issue #153): a ``` line that opens no fence (backtick in its info string)
  # does not pair its last backtick with the next line, though CommonMark does.
  printf '```cmd `\nsee <k> ` tail\n' > "$T/in.md"
  visible "F1 over-lint: backtick run that opens no fence" '<k>'
  # S1 (over-lint, issue #153): a span wrapping after a setext underline is not stripped.
  printf 'title\n===\nx `a <k>\nb` c\n' > "$T/in.md"
  visible "S1 over-lint: wrap after a setext underline" '<k>'
  # S2 (over-lint, issue #153): nor after a bare numbered marker.
  printf '1.\nx `a <k>\nb` c\n' > "$T/in.md"
  visible "S2 over-lint: wrap after a bare numbered marker" '<k>'
  # S3 (over-lint, issue #153): nor after a CRLF bare list marker.
  printf -- '-\r\nx `a <k>\r\nb` c\r\n' > "$T/in.md"
  visible "S3 over-lint: wrap after a CRLF bare marker" '<k>'
  # P4 (over-lint, issue #153): a span wrapping later in a paragraph is not stripped.
  printf 'line one\nsee `foo <k>\nbar` end\n' > "$T/in.md"
  visible "P4 over-lint: wrap later in a paragraph" '<k>'
  # FR1 (over-lint, issue #153): a span wrapping after a closed fence is not stripped.
  printf '# h\n~~~\nx\n~~~\nsee `foo <k>\nbar` end\n' > "$T/in.md"
  visible "FR1 over-lint: wrap after a fence closes" '<k>'
  # A1-A3: lines after a fence inside an HTML block never pair (A1, A2 red on ac6fe77;
  # A2 in a list item, A3 quoted).
  printf '<div>\n```\nx\n```\nfoo `a\nb <real> ` c\n</div>\n' > "$T/in.md"
  visible "A1 fence inside an HTML block" '<real>'
  printf -- '- <div>\n  ```\n  x\n  ```\n  foo `a\n  b <real> ` c\n  </div>\n' > "$T/in.md"
  visible "A2 fence inside an HTML block in a list item" '<real>'
  printf '> <div>\n> ```\n> x\n> ```\n> foo `a\n> b <real> ` c\n> </div>\n' > "$T/in.md"
  visible "A3 fence inside a quoted HTML block" '<real>'
  # HP1-HP3: an HTML block such as <pre> runs across blank lines; its lines never pair
  # (HP1, HP2 red on ac6fe77).
  printf '<pre>\n\nfoo `a\nb <real> ` c\n</pre>\n' > "$T/in.md"
  visible "HP1 blank line inside <pre>" '<real>'
  printf -- '- a\n\n  <pre>\n\n  foo `a\n  b <real> ` c\n  </pre>\n' > "$T/in.md"
  visible "HP2 blank line inside an indented <pre>" '<real>'
  printf '> <pre>\n>\n> foo `a\n> b <real> ` c\n> </pre>\n' > "$T/in.md"
  visible "HP3 blank line inside a quoted <pre>" '<real>'
  # D1-D8: the lines above a table delimiter row never pair; GFM may read the last of them
  # as a header (D1, D2, D5, D7, D8 red on ac6fe77; D6 quoted).
  printf 'see `x <real>\nh ` y\n:-:\n' > "$T/in.md"
  visible "D1 delimiter row under a wrapped span" '<real>'
  printf 'see `x <real>\nh ` y\n|-|\n' > "$T/in.md"
  visible "D2 piped delimiter row under a wrapped span" '<real>'
  printf 'see `x <real>\nh ` y\n-:\n' > "$T/in.md"
  visible "D5 right-aligned delimiter row under a wrapped span" '<real>'
  printf '> see `x <real>\n> h ` y\n> :-:\n' > "$T/in.md"
  visible "D6 quoted delimiter row under a wrapped span" '<real>'
  printf -- '- a\n\n  see `x <real>\n  h ` y\n  :-:\n' > "$T/in.md"
  visible "D7 delimiter row in a list item" '<real>'
  printf 'line one\nsee `x <real>\nh ` y\n:-:\n' > "$T/in.md"
  visible "D8 delimiter row under a three-line run" '<real>'
  # D3, D4 (over-lint, issue #153): under --- or === the two lines are a setext heading where
  # the span does wrap; it is not stripped.
  printf 'see `x <k>\nh ` y\n---\n' > "$T/in.md"
  visible "D3 over-lint: setext --- under a wrapped span" '<k>'
  printf 'see `x <k>\nh ` y\n===\n' > "$T/in.md"
  visible "D4 over-lint: setext === under a wrapped span" '<k>'
  # D9: a span inside a lone header line is still stripped.
  printf 'h `a <k>` y\n:-:\n' > "$T/in.md"
  hidden "D9 span in a lone header line" '<k>'
  # HL1, HL2: <pre> after a list marker, or indented 4 columns in a list item, runs across
  # blank lines; its lines never pair (red on 2e7f275).
  printf -- '- <pre>\n\n  foo `a\n  b <real> ` c\n  </pre>\n' > "$T/in.md"
  visible "HL1 <pre> after a list marker" '<real>'
  printf -- '- a\n\n    <pre>\n\n  foo `a\n  b <real> ` c\n  </pre>\n' > "$T/in.md"
  visible "HL2 <pre> indented 4 columns in a list item" '<real>'
  # FN1, LR1: a footnote or link reference definition line never pairs with a neighbour
  # (red on 2e7f275).
  printf 'see `x <real>\n[^1]: y ` z\n' > "$T/in.md"
  visible "FN1 footnote definition after a line" '<real>'
  printf '[a `x <real>]: /u\nb ` c\n' > "$T/in.md"
  visible "LR1 link reference definition" '<real>'
  # P5 (over-lint, issue #153): a span wrapping after a line starting with a digit is not stripped.
  printf '3.14 `x <k>\npi ` z\n' > "$T/in.md"
  visible "P5 over-lint: wrap after a line starting with a digit" '<k>'
  # CR1: the lines above a CRLF delimiter row never pair.
  printf 'see `x <real>\r\nh ` y\r\n:-:\r\n' > "$T/in.md"
  visible "CR1 CRLF delimiter row under a wrapped span" '<real>'
  # S4 (over-lint, issue #153): a span wrapping after a CRLF bare numbered marker is not stripped.
  printf '1.\r\nx `a <k>\r\nb` c\r\n' > "$T/in.md"
  visible "S4 over-lint: wrap after a CRLF bare numbered marker" '<k>'
  # W1-W3 (over-lint, issue #153): a span wrapping on a line that starts with emphasis (W1)
  # or a code span (W2), or whose closer starts the next line (W3), is not stripped.
  printf '**Note** see `foo <k>\nbar` end\n' > "$T/in.md"
  visible "W1 over-lint: line starting with emphasis" '<k>'
  printf '`x` and `foo <k>\nbar` end\n' > "$T/in.md"
  visible "W2 over-lint: line starting with a code span" '<k>'
  printf 'see `foo <k>\n` end\n' > "$T/in.md"
  visible "W3 over-lint: closing backtick at the start of the next line" '<k>'
  # IP1-IP6: a raw HTML tag (IP1, IP4-IP6), autolink (IP2) or comment (IP3) holding a
  # backtick never lets that backtick pair with the next line (IP1-IP4 red on 9c22fb1).
  printf 'see <a href="`x"> <real>\nb ` c\n' > "$T/in.md"
  visible "IP1 backtick inside a raw HTML tag" '<real>'
  printf 'see <http://h/`a> <real>\nb ` c\n' > "$T/in.md"
  visible "IP2 backtick inside an autolink" '<real>'
  printf 'see <!-- `x --> <real>\nb ` c\n' > "$T/in.md"
  visible "IP3 backtick inside an HTML comment" '<real>'
  printf 'see `a` <a href="`x"> <real>\nb ` c\n' > "$T/in.md"
  visible "IP4 closed span before the tag" '<real>'
  # P6, P7 (over-lint, issue #153): a wrapping span is not stripped, whatever < it holds
  # after the opener (P6) or inside a closed span before it (P7).
  printf 'see `x <p>\nb` c\n' > "$T/in.md"
  visible "P6 over-lint: placeholder after the opener" '<p>'
  printf 'see `<a>` and `x <k>\nb` c\n' > "$T/in.md"
  visible "P7 over-lint: < inside an earlier closed span" '<k>'
  # WB1-WB6: a tag or comment holding a backtick, after a wrapped span or opened on the line
  # before, never lets that backtick pair with another line; GitHub renders <real> there as
  # raw HTML (red on dca49f6).
  printf 'see `x\ny` <a href="`z"> <real>\nb ` c\n' > "$T/in.md"
  visible "WB1 tag after a wrapped span" '<real>'
  printf 'see `x\ny` <a href="`z"> <real> ` q\nb ` c\n' > "$T/in.md"
  visible "WB2 span on the closing line of a wrapped span" '<real>'
  printf 'see <a\nhref="`x"> <real>\nb ` c\n' > "$T/in.md"
  visible "WB3 tag opened on the line before" '<real>'
  printf 'see <!-- a\nb `x --> <real>\nc ` d\n' > "$T/in.md"
  visible "WB4 comment opened on the line before" '<real>'
  printf 'see <a\nhref="`x"> <real> <\nb ` c\n' > "$T/in.md"
  visible "WB5 depth below zero, back to zero at the closer" '<real>'
  printf 'see <a\nhref="`<<x"> <real>\nb ` c\n' > "$T/in.md"
  visible "WB6 depth above zero at the closer" '<real>'
  # IP5, IP6: a < after the backtick inside the tag (see IP1-IP6).
  printf 'see <a href="`<x"> <real>\nb ` c\n' > "$T/in.md"
  visible "IP5 tag text balanced after the backtick" '<real>'
  printf 'see `a` <a href="`<x"> <real>\nb ` c\n' > "$T/in.md"
  visible "IP6 IP5 after a closed span" '<real>'
  # P8 (over-lint, issue #153): a wrapped span holding balanced tags is not stripped.
  printf 'see `x <b>y</b> <p>\nz` end\n' > "$T/in.md"
  visible "P8 over-lint: balanced tags inside a wrapped span" '<p>'
  # P9 (over-lint, issue #153): a span closed within its own line, in a paragraph where an
  # earlier line left a backtick unmatched, is printed raw too, so its <k> stays visible.
  printf 'see `x\ny` z\nw `<k> >` c\n' > "$T/in.md"
  visible "P9 over-lint: one-line span after a lone backtick in the paragraph" '<k>'
  # P9b-P9d: the same span after a blank line still strips (the raw print ends at a blank
  # line; spaces, tabs and a CRLF line end count as blank).
  printf 'see `x\ny` z\n\nw `<k> >` c\n' > "$T/in.md"
  hidden "P9b one-line span in the next paragraph" '<k>'
  printf 'see `x\ny` z\n \t\nw `<k> >` c\n' > "$T/in.md"
  hidden "P9c blank line of a space and a tab" '<k>'
  printf 'see `x\r\ny` z\r\n\r\nw `<k> >` c\r\n' > "$T/in.md"
  hidden "P9d CRLF blank line" '<k>'
  # P9e: a lone backtick changes nothing on its own line; a span before it still strips.
  printf 'ran `cat <k>` and a lone ` here\n' > "$T/in.md"
  hidden "P9e one-line span before a lone backtick" '<k>'
  # P10 (over-lint, issue #153): <k> inside a wrapped span stays visible.
  printf 'see `x <k>\ny` z\nw `a >` c\n' > "$T/in.md"
  visible "P10 over-lint: placeholder in the wrap, span on the line after" '<k>'
  # X1, X2: a backtick that would close a wrapped span never pairs onward over <real> on
  # the next line (red on c1a32c2).
  printf 'see `a <\nb` then <real>\nc ` d\n' > "$T/in.md"
  visible "X1 rejected wrap does not shift the pairing" '<real>'
  printf 'see `x\ny` p `a >` then <real>\nc ` d\n' > "$T/in.md"
  visible "X2 rejected span after a wrap does not shift the pairing" '<real>'
  # WZ1 (over-lint, issue #153): GitHub renders `x y <k` as code, but the span wraps a line
  # break, so <k` z> stays visible.
  printf 'see `x\ny <k` z>\n' > "$T/in.md"
  visible "WZ1 over-lint: < open at the closer" '<k` z>'
  # J1-J6: a raw HTML tag, comment or processing instruction that opens on one line and holds
  # a backtick, with a < after that backtick, hid <real> under a design that joined lines
  # to match wrapped spans; stripping each line alone keeps it visible, as main a2d4029 does.
  printf 'see <a\nhref="`<x"> <real>\nb ` c\n' > "$T/in.md"
  visible "J1 tag opened on the line before, < after the backtick" '<real>'
  printf 'see <!-- a\nb `<x --> <real>\nc ` d\n' > "$T/in.md"
  visible "J2 comment opened on the line before, < after the backtick" '<real>'
  printf 'see `x\ny` <a href="`<z"> <real> ` q\nb ` c\n' > "$T/in.md"
  visible "J3 tag after a wrapped span, < after the backtick" '<real>'
  printf 'see <?\nb `<x ?> <real>\nc ` d\n' > "$T/in.md"
  visible "J4 processing instruction opened on the line before" '<real>'
  printf 'see `a\nb` <a href="`<x"> <real>\nc ` d\n' > "$T/in.md"
  visible "J5 tag on the closing line of a wrapped span" '<real>'
  printf 'see <x-y\nz="`<<a>"> <real>\nb ` c\n' > "$T/in.md"
  visible "J6 custom tag opened on the line before" '<real>'
  # XF0-XF2: a backtick left unmatched on one line pairs, on GitHub, with the first backtick
  # of a later line in the same paragraph, so a span stripped on that later line on its own
  # is not code there and its <real> shows as raw HTML; every later line of the paragraph is
  # also linted raw. All red on 92ad0e6. XF1 puts a 4-column ``` line between (opens no
  # fence, issue #149 item 3); main a2d4029 refuses XF1 only through its unclosed-fence dump
  # and passes XF0. XF2 is XF0 with CRLF line ends.
  printf 'Ran it on `main\n`x <real>` passed.\n' > "$T/in.md"
  visible "XF0 unmatched backtick pairs with a later line" '<real>'
  printf 'Ran the suite on `main\n    ```\n`code <real>` and it passed.\n' > "$T/in.md"
  visible "XF1 unmatched backtick across a 4-column fence-like line" '<real>'
  printf 'Ran it on `main\r\n`x <real>` passed.\r\n' > "$T/in.md"
  visible "XF2 XF0 with CRLF line ends" '<real>'
  # XF3 (guard): XF0 split by a bare CR inside one LF line; the whole-line strip pairs across
  # the CR as GitHub does and keeps <real>.
  printf 'Ran it on `main\r`x <real>` passed.\n' > "$T/in.md"
  visible "XF3 XF0 split by a bare CR" '<real>'
  # XF4 (over-lint pin): the whole-LF-line pass prints raw too. The CR-split pass takes the
  # ``` after the mid-line CR for a fence and hides line 3, as GitHub does; only the raw
  # print of the whole-line pass keeps <real> (red on 92ad0e6).
  printf 'a `x\nb\r```\n`y <real>`\n```\n' > "$T/in.md"
  visible "XF4 over-lint: raw print in the whole-line pass" '<real>'
  # XF5, XF6: a line of only a form feed or a vertical tab is not blank in CommonMark, so
  # the paragraph runs on and the raw print does too (red on 92ad0e6).
  printf 'Ran it on `main\n\f\n`x <real>` passed.\n' > "$T/in.md"
  visible "XF5 form feed line does not end the paragraph" '<real>'
  printf 'Ran it on `main\n\v\n`x <real>` passed.\n' > "$T/in.md"
  visible "XF6 vertical tab line does not end the paragraph" '<real>'
  # FC1, FC2: a fence at 3 columns or less ends the paragraph, so a backtick left unmatched
  # before it pairs with nothing after it and the span there still strips (red on a56e54c).
  # In FC2 the fence line follows a CR in the record that holds the unmatched backtick.
  printf 'Note `unfinished\n~~~\ncode\n~~~\nUse `<k>`.\n' > "$T/in.md"
  hidden "FC1 fence ends the paragraph" '<k>'
  printf 'Note `unfinished\r~~~\ncode\n~~~\nUse `<k>`.\n~~~\n' > "$T/in.md"
  hidden "FC2 fence after a CR ends the paragraph" '<k>'
  # FC3-FC5 (guards): a ~~~ line at 4 columns is paragraph text on GitHub, so the paragraph
  # runs on (main a2d4029 takes it for a fence and hides <real>); so does a paragraph that
  # starts after a fence, or inside a list fence whose item ended before its 4-column closer.
  printf 'Ran it on `main\n    ~~~\nx\n    ~~~\n`code <real>` passed.\n' > "$T/in.md"
  visible "FC3 ambiguous fence line does not end the paragraph" '<real>'
  printf '~~~\ncode\n~~~\nRan it on `main\n`x <real>` passed.\n' > "$T/in.md"
  visible "FC4 unmatched backtick after a fence" '<real>'
  printf -- '- item\n  ~~~\n  code\n\nRan it on `main\n    ~~~\n`x <real>` passed.\n' > "$T/in.md"
  visible "FC5 unmatched backtick in the body before an ambiguous closer" '<real>'
  # FS1: an awk that fails in any one pass, or in the CR probe, makes the strip fail (the
  # caller then refuses instead of linting partial text).
  printf 'plain <real>\r\n' > "$T/in.md"
  for bad in mode=split mode=whole mode=main probe; do
    awk() { case "$bad:$1:$2" in probe:-v:*) ;; probe:*) return 2 ;; *:-v:"$bad") return 2 ;; esac; command awk "$@"; }
    if strip_code_spans "$T/in.md" > "$T/out"; then echo "FAIL: FS1 a failed awk ($bad) did not fail the strip"; exit 1; fi
  done
  unset -f awk
  echo PASS
expected: exit 0; stdout "PASS". strip_code_spans matches a code span within one line only: every line outside a fence is stripped on its own, as on main a2d4029, whose own parse also runs on every file and is printed too (fixture 360 M1, M2 pin that pass; 360 also pins the fence indent rule). No line is ever joined to the next, so no span is matched across a line break. Fail-safe over-lint, issue #153: a span that wraps a line break, which CommonMark and GitHub render as code, is not stripped, so a placeholder inside it stays visible and the lint refuses the evidence; the positives P1, P4-P8, P10 and T4 pin that (each asserts its <k> or <p> stays visible), alongside the earlier pins L1, P3, T5, LH1, F1, S1-S4, FR1, D3, D4, W1-W3 and WZ1. Issue #149 item 1 (let a span wrap a line break) was dropped: every design that joined lines to match a wrapped span had a path that hid a real placeholder relative to main (a raw HTML tag, comment or processing instruction opened on one line and holding a backtick). Guards, each asserting <real> stays visible and each passing here: R1-R8, B1, B2, T1, T2, H1, H2, G1-G16b (G2b a nested list marker under a nested item), LM1-LM13, Q1, Q1b, A1-A3, HP1-HP3, D1, D2, D5-D8, HL1, HL2, FN1, LR1, CR1, IP1-IP6, WB1-WB6, X1, X2, and J1-J6 (a tag, comment or processing instruction opened on the line before a backtick, with a < after the backtick; each hid <real> under a join design, and passes on main and here). P2 keeps text after an unclosed backtick linted. One-line spans still strip: T3, D9, P9b-P9e. Cross-line pairing the other way (issue #153): GitHub can pair a backtick left unmatched on one line with the first backtick of a later line in the same paragraph, so a span this strip removes from that later line is not code there. Once a line leaves a backtick run unmatched, every later line up to the next blank line (spaces, tabs and a CR only) or fence opener is printed raw as well as stripped, in the CR-split pass and in the whole-LF-line pass: XF0, XF1 (a 4-column ``` line between), XF2 (CRLF), XF5 and XF6 (a form feed or vertical tab line between, not blank in CommonMark) keep <real> visible as GitHub shows it, and XF4 pins the whole-line pass. XF0-XF2, XF4-XF6 and P9 are red on 92ad0e6; main a2d4029 hides the token in each of them except XF1, which it shows only through its unclosed-fence dump. XF3 (a bare CR mid-line) is a guard. P9 (over-lint, issue #153) pins the cost: its one-line span follows a lone backtick in the same paragraph, so its <k> stays visible; P9b-P9d, the same span after a blank line, and P9e still strip. Mutations (on copies of scripts/pr-delivery.sh, every row run): never setting the paragraph flag fails P9, XF0, XF2, XF4, XF5, XF6 and FC3-FC5 (XF1 is also kept by the main pass); never clearing it fails P9b-P9d; clearing it on any [[:space:]] line fails XF5 and XF6; only on an empty line P9c and P9d; not on a CR P9d; printing raw one line after only fails XF5, XF6 and FC3; printing the line that sets the flag raw fails P9e; raw in the CR-split pass only fails XF4; in the whole-line pass only fails P9, XF0, XF5, XF6 and FC3-FC5. A fence opener at 3 columns or less ends the paragraph, so it ends the raw print: FC1 and FC2 (the fence line after a CR) strip the span after the fence, as GitHub renders FC1 (both red on a56e54c). FC3-FC5 keep <real> visible, as GitHub does: a 4-column ~~~ line in the paragraph, a paragraph after a fence, and one in the body before an ambiguous closer; all pass on a56e54c and main a2d4029 hides all three. An opener inside an HTML block, which GitHub does not read as a fence, clears the flag too; main hides the span after it as well. Mutations: not clearing at the opener fails FC1 and FC2; clearing before the pieces ahead of the opener are printed FC2; clearing at an ambiguous opener FC3; clearing at the closer FC5; no raw print after a first fence FC4 and FC5. FS1: an awk that fails in any one pass, or in the CR probe, fails the strip; dropping `|| return 1` after the program or after the probe fails FS1. A minimal join that strips each pair of consecutive non-blank lines outside fences together, in every pass, makes this fixture exit 1, the first failure P1; with every row run, the wrap pins P1, T4, P5-P8, P10 fail (P4 passes: the pairwise join pairs its first two lines) with most earlier #153 pins and most guards, J3 among them (J1, J2, J4-J6 pass on that naive pairwise join, because their backtick closer sits on the third line). The same join in the CR-split pass alone fails only P9: the main pass still prints every line stripped on its own.
