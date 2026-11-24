name: pr-delivery.sh placeholder strip checks each line on its own and lets a code span wrap one line break only between two plain paragraph lines with no non-plain line since the last blank line or fence end (design A)
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
  # L1 (over-lint, issue #153): an indented line is not plain, so a span does not wrap onto
  # a lazy continuation line, though CommonMark would close it there.
  printf 'see `foo <k>\n    bar` end\n' > "$T/in.md"
  visible "L1 over-lint: lazy indented continuation" '<k>'
  # G1: a bare list or quote marker is not paragraph text, so the indented line after it is code.
  printf -- '-\n      cmd `\nsee <real> ` tail\n' > "$T/in.md"
  visible "G1 indented code after a bare list marker" '<real>'
  printf '>\n      cmd `\nsee <real> ` tail\n' > "$T/in.md"
  visible "G1b indented code after a bare quote marker" '<real>'
  # G2: an indented line that starts a block (a nested list item) never joins.
  printf -- '- a `x <real>\n    - b` c\n' > "$T/in.md"
  visible "G2 indented nested list item" '<real>'
  # P3 (over-lint, issue #153): a line holding a pipe is not plain, even in prose.
  printf 'ran `cat x <k> |\ngrep y` done\n' > "$T/in.md"
  visible "P3 over-lint: prose with a pipe" '<k>'
  # G3: a header line holding a pipe is not plain, so a span opened on the line before it
  # cannot close in it.
  printf 'see `x <real>\na ` | b\n--- | ---\n' > "$T/in.md"
  visible "G3 header split from the line before" '<real>'
  # G4: a table inside a block quote: every line is a quote line and stands alone.
  printf '> a | b\n> --- | ---\n> x | y\n> z ` | w\nnext <real> ` tail\n' > "$T/in.md"
  visible "G4 table in a block quote" '<real>'
  # G5: rows after a pipe header stand alone up to a blank line, pipe or no pipe.
  printf '| a |\n---\nx ` <real>\ny ` z\n' > "$T/in.md"
  visible "G5 pipe-less delimiter under a pipe header" '<real>'
  # T5 (over-lint, issue #153): only a blank line ends the stand-alone run, not a heading.
  printf 'a | b\n--- | ---\nx | y\n# Next\nsee `foo <k>\nbar` end\n' > "$T/in.md"
  visible "T5 over-lint: heading after a table" '<k>'
  # G6, G7: rows after a table stand alone up to a blank line, whatever lines come between.
  printf 'a | b\n--- | ---\n####### x\np ` <real>\nq ` r\n' > "$T/in.md"
  visible "G6 seven hashes stay a row" '<real>'
  printf 'a | b\n--- | ---\n#x\np ` <real>\nq ` r\n' > "$T/in.md"
  visible "G7 hash without a blank stays a row" '<real>'
  # G8: a heading line stands alone.
  printf 'a | b\n--- | ---\n# h `x <real>\nb` c\n' > "$T/in.md"
  visible "G8 heading after a table stands alone" '<real>'
  # G10-G13: an indented line (code) after a setext underline, a thematic break, or a
  # heading or rule inside a list item stands alone.
  printf 'title\n---\n    cmd `\nsee <real> ` tail\n' > "$T/in.md"
  visible "G10 indented code after a setext underline" '<real>'
  printf 'para\n***\n    cmd `\nsee <real> ` tail\n' > "$T/in.md"
  visible "G11 indented code after a thematic break" '<real>'
  printf -- '- # h\n      cmd `\nsee <real> ` tail\n' > "$T/in.md"
  visible "G12 indented code after a list-item heading" '<real>'
  printf -- '- a\n    ***\n      cmd `\nsee <real> ` tail\n' > "$T/in.md"
  visible "G13 indented code after a list-item rule" '<real>'
  # G14: rows of a table inside a list item stand alone up to a blank line.
  printf -- '- x\n    a | b\n    --|--\n  p ` <real> | y\n  z ` | w\n' > "$T/in.md"
  visible "G14 indented table in a list item" '<real>'
  # G15: the same after a pipe-less delimiter under a solo pipe header.
  printf -- '- x\n    | a |\n    ---\n  p ` <real>\n  z ` w\n' > "$T/in.md"
  visible "G15 pipe-less delimiter under a solo pipe header" '<real>'
  # G16: CRLF line ends change none of the plain line tests.
  printf 'a | b\r\n--- | ---\r\nx ` <real>\r\nz ` w\r\n' > "$T/in.md"
  visible "G16 CRLF table" '<real>'
  printf -- '-\r\n      cmd `\r\nsee <real> ` tail\r\n' > "$T/in.md"
  visible "G16b CRLF bare list marker" '<real>'
  # G9: lines of an HTML block stand alone up to a blank line, a heading among them or not.
  printf '<div>\n# h\nfoo `a\nb <real> ` c\n</div>\n' > "$T/in.md"
  visible "G9 heading inside an HTML block" '<real>'
  # LM1-LM13: a list marker or quote line is not plain; the next line never closes a span
  # opened in it, and lines after it stand alone up to a blank line (LM5).
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
  # LH1 (over-lint, issue #153): a list item line is not plain, so its span does not wrap
  # onto the continuation line.
  printf -- '- see `foo <k>\n  bar` end\n' > "$T/in.md"
  visible "LH1 over-lint: span in a list item" '<k>'
  # Design A. Q1: indented code on a list marker line never joins the next line (red on
  # 1246656); Q1b the same inside a block quote.
  printf -- '-     cmd `\nsee <real> ` tail\n' > "$T/in.md"
  visible "Q1 indented code after a list marker" '<real>'
  printf -- '> -     cmd `\n> see <real> ` tail\n' > "$T/in.md"
  visible "Q1b quoted indented code after a list marker" '<real>'
  # F1 (over-lint, issue #153): a ``` line that opens no fence (backtick in its info string)
  # is not plain, though CommonMark pairs its last backtick with the next line's.
  printf '```cmd `\nsee <k> ` tail\n' > "$T/in.md"
  visible "F1 over-lint: backtick run that opens no fence" '<k>'
  # S1 (over-lint, issue #153): a setext underline is not plain and the lines after it up
  # to a blank line stand alone.
  printf 'title\n===\nx `a <k>\nb` c\n' > "$T/in.md"
  visible "S1 over-lint: wrap after a setext underline" '<k>'
  # S2 (over-lint, issue #153): a bare numbered marker with nothing after it is not plain.
  printf '1.\nx `a <k>\nb` c\n' > "$T/in.md"
  visible "S2 over-lint: wrap after a bare numbered marker" '<k>'
  # S3 (over-lint, issue #153): a CRLF line end does not make a bare marker plain.
  printf -- '-\r\nx `a <k>\r\nb` c\r\n' > "$T/in.md"
  visible "S3 over-lint: wrap after a CRLF bare marker" '<k>'
  # P4: a span wraps the break between two plain lines anywhere in a run of plain lines.
  printf 'line one\nsee `foo <k>\nbar` end\n' > "$T/in.md"
  hidden "P4 wrap later in a paragraph" '<k>'
  # FR1: the end of a fence ends the stand-alone run, like a blank line.
  printf '# h\n~~~\nx\n~~~\nsee `foo <k>\nbar` end\n' > "$T/in.md"
  hidden "FR1 wrap after a fence closes" '<k>'
  echo PASS
expected: exit 0; stdout "PASS". Design A: strip_code_spans strips every line on its own, as main a2d4029 did, except that a run of plain paragraph lines is stripped together so a span may wrap the one line break between two of them (P1, P4) while text after the span is still linted (P2). A line is plain when it is indented 3 columns or less, not blank, has no list item marker (-, *, + or digits then . or ), followed by a blank or end of line) or > marker, holds no |, does not start with #, <, ``` or ~~~, and is not made only of - _ * = : | and blanks (trailing whitespace, CR included, trimmed first). Once a non-plain line appears, every line up to the next blank line or the end of a fence stands alone (T2, H2, G5-G9, G15, G16, LM5), and a blank line or a closed fence starts joining again (T4, FR1). A span crosses at most one line break (R2) and never a blank line (R1) or a fence (R3); an unclosed span is printed whole (R7) and an escaped backtick opens nothing (R8). Every fail-open guard keeps <real> visible: R4-R6, B1, T1, T2, H1, H2, G1-G16b, LM1-LM13, Q1 and Q1b (indented code on a list marker line, plain or quoted; Q1 is red on 1246656). Documented over-lint (issue #153): a span does not strip where CommonMark would close it across a lazy indented line (L1), a line holding a pipe (P3), a run after a table ended by a heading (T5), a list item line (LH1), a ``` line that opens no fence (F1), or the lines after a setext underline (S1), a bare numbered marker (S2) or a CRLF bare marker (S3); each asserts that <k> stays visible. Mutation (each on a copy of scripts/pr-delivery.sh): indent test always true -> B1 fails; drop the list marker test -> R4, Q1 and LM1 fail; drop *, +, the dot or the paren -> LM7, LM8, LM9 or LM10 fails; require a blank after the marker (no end of line) -> S2 fails; drop > -> R5, Q1b and LM13 fail; drop # -> R6 fails; drop < -> H1 and H2 fail; drop the pipe test -> G3 fails; drop the ``` test -> F1 fails; drop the rule test -> S1 fails; drop the trailing trim -> S3 fails; let a plain line join after a non-plain one -> T2 fails; no reset at a blank line -> T4 fails; no reset at a fence end -> FR1 fails; no flush at a blank line -> R1 fails, before a fence -> R3 fails; no one-break limit -> R2 fails; never join -> P1 fails. The ```, rule, end-of-line and trim clauses guard no fail-open on their own (their killing cases are over-lint pins); the ~~~ test cannot be reached (a ~~~ run at 3 columns or less always opens a fence first), so dropping it changes nothing.
