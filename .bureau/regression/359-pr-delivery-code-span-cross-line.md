name: pr-delivery.sh placeholder strip checks each line on its own and lets a code span wrap one line break only between two plain lines (an ASCII letter or digit first) with no non-plain line since the last blank line, none after a line starting with < behind any indent or list and quote markers, and none above a delimiter row (design A, plain whitelist)
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
  # FR1 (over-lint, issue #153): the end of a fence does not end the stand-alone run; only
  # a blank line does, so a span after the fence does not wrap though CommonMark would.
  printf '# h\n~~~\nx\n~~~\nsee `foo <k>\nbar` end\n' > "$T/in.md"
  visible "FR1 over-lint: wrap after a fence closes" '<k>'
  # A1-A3: a fence inside an HTML block does not end the stand-alone run (A1 red on ac6fe77;
  # A2 red there too, inside a list item, where no line starts with <; A3 quoted).
  printf '<div>\n```\nx\n```\nfoo `a\nb <real> ` c\n</div>\n' > "$T/in.md"
  visible "A1 fence inside an HTML block" '<real>'
  printf -- '- <div>\n  ```\n  x\n  ```\n  foo `a\n  b <real> ` c\n  </div>\n' > "$T/in.md"
  visible "A2 fence inside an HTML block in a list item" '<real>'
  printf '> <div>\n> ```\n> x\n> ```\n> foo `a\n> b <real> ` c\n> </div>\n' > "$T/in.md"
  visible "A3 fence inside a quoted HTML block" '<real>'
  # HP1-HP3: an HTML block such as <pre> runs across blank lines, so once a line starts
  # with < (after up to 3 columns) no line joins again (HP1 and HP2 red on ac6fe77).
  printf '<pre>\n\nfoo `a\nb <real> ` c\n</pre>\n' > "$T/in.md"
  visible "HP1 blank line inside <pre>" '<real>'
  printf -- '- a\n\n  <pre>\n\n  foo `a\n  b <real> ` c\n  </pre>\n' > "$T/in.md"
  visible "HP2 blank line inside an indented <pre>" '<real>'
  printf '> <pre>\n>\n> foo `a\n> b <real> ` c\n> </pre>\n' > "$T/in.md"
  visible "HP3 blank line inside a quoted <pre>" '<real>'
  # D1-D8: a line made only of - _ * = : | and blanks after a run of plain lines can be a
  # table delimiter row whose header is the run's last line (GFM), so every line of the run
  # is stripped alone (D1, D2, D5, D7, D8 red on ac6fe77; D6 quoted).
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
  # D3, D4 (over-lint, issue #153): under --- or === the run is a setext heading where the
  # span does wrap; it is stripped line by line all the same.
  printf 'see `x <k>\nh ` y\n---\n' > "$T/in.md"
  visible "D3 over-lint: setext --- under a wrapped span" '<k>'
  printf 'see `x <k>\nh ` y\n===\n' > "$T/in.md"
  visible "D4 over-lint: setext === under a wrapped span" '<k>'
  # D9: a span inside a lone header line is still stripped.
  printf 'h `a <k>` y\n:-:\n' > "$T/in.md"
  hidden "D9 span in a lone header line" '<k>'
  # Plain whitelist. HL1, HL2: a < after list markers, or indented 4 columns inside a list
  # item, starts an HTML block such as <pre> that runs across blank lines (red on 2e7f275).
  printf -- '- <pre>\n\n  foo `a\n  b <real> ` c\n  </pre>\n' > "$T/in.md"
  visible "HL1 <pre> after a list marker" '<real>'
  printf -- '- a\n\n    <pre>\n\n  foo `a\n  b <real> ` c\n  </pre>\n' > "$T/in.md"
  visible "HL2 <pre> indented 4 columns in a list item" '<real>'
  # FN1, LR1: a footnote or link reference definition line starts with [, so it is not
  # plain and never joins (red on 2e7f275).
  printf 'see `x <real>\n[^1]: y ` z\n' > "$T/in.md"
  visible "FN1 footnote definition after a line" '<real>'
  printf '[a `x <real>]: /u\nb ` c\n' > "$T/in.md"
  visible "LR1 link reference definition" '<real>'
  # P5: a line starting with a digit (not a list marker) is plain, so the span wraps.
  printf '3.14 `x <k>\npi ` z\n' > "$T/in.md"
  hidden "P5 wrap after a line starting with a digit" '<k>'
  # CR1: a CRLF delimiter row still splits the run above it.
  printf 'see `x <real>\r\nh ` y\r\n:-:\r\n' > "$T/in.md"
  visible "CR1 CRLF delimiter row under a wrapped span" '<real>'
  # S4 (over-lint, issue #153): a CRLF bare numbered marker is not plain.
  printf '1.\r\nx `a <k>\r\nb` c\r\n' > "$T/in.md"
  visible "S4 over-lint: wrap after a CRLF bare numbered marker" '<k>'
  # W1-W3 (over-lint, issue #153): a line whose first character is not an ASCII letter or
  # digit is not plain, though CommonMark wraps the span there.
  printf '**Note** see `foo <k>\nbar` end\n' > "$T/in.md"
  visible "W1 over-lint: line starting with emphasis" '<k>'
  printf '`x` and `foo <k>\nbar` end\n' > "$T/in.md"
  visible "W2 over-lint: line starting with a code span" '<k>'
  printf 'see `foo <k>\n` end\n' > "$T/in.md"
  visible "W3 over-lint: closing backtick at the start of the next line" '<k>'
  echo PASS
expected: exit 0; stdout "PASS". Design A with a plain whitelist: strip_code_spans strips every line on its own, as main a2d4029 did, except that a run of plain lines is stripped together so a span may wrap the one line break between two of them (P1, P4, P5) while text after the span is still linted (P2). A line is plain only when, after an indent of 3 columns or less, its first character is an ASCII letter or digit, it is not an ordered list marker line (digits, then . or ), then a blank or end of line; trailing whitespace, CR included, trimmed first) and it holds no |. Every other line is not plain: list and quote markers, headings, HTML, fences, footnote and link reference definitions (FN1, LR1), emphasis, a leading backtick. Once a non-plain line appears, every line up to the next blank line stands alone, a closed fence among them or not (T2, H2, G5-G9, G15, G16, LM5, A1-A3), and a blank line starts joining again (T4). Once a line starts with <, at any indent and after any run of list or quote markers, no line joins for the rest of the file, blank lines included (HP1-HP3, HL1, HL2). A line made only of - _ * = : | and blanks strips each line of the run above it alone, since GFM may read the run's last line as a table header (D1, D2, D5-D8, CR1); a span in a lone header line still strips (D9). A span crosses at most one line break (R2) and never a blank line (R1) or a fence (R3); an unclosed span is printed whole (R7) and an escaped backtick opens nothing (R8). Every fail-open guard keeps <real> visible: R4-R6, B1, T1, T2, H1, H2, G1-G16b, LM1-LM13, Q1, Q1b, A1-A3, HP1-HP3, D1, D2, D5-D8, HL1, HL2, FN1, LR1, CR1 (HL1, HL2, FN1 and LR1 are red on 2e7f275; earlier: Q1 red on 1246656; A1, A2, HP1, HP2, D1, D2, D5, D7, D8 red on ac6fe77). Documented over-lint (issue #153), each asserting that <k> stays visible: a lazy indented line (L1), a line holding a pipe (P3), a run after a table ended by a heading (T5), a list item line (LH1), a ``` line that opens no fence (F1), the lines after a setext underline (S1), a bare numbered marker (S2, CRLF S4) or a CRLF bare marker (S3), after a closed fence until a blank line (FR1), a two-line setext heading under --- or === (D3, D4), and a line whose first character is not an ASCII letter or digit (W1 emphasis, W2 leading code span, W3 closing backtick first on the next line). Mutation (each on a copy of scripts/pr-delivery.sh; failing cases from a collected run, and the committed fixture exits 1 for each unless noted): accept any first character -> R4-R6, LM1-LM3, LM7, LM8, LM11-LM13, Q1, Q1b, FN1, LR1, CR1 and others fail; restore the old blacklist plain test with the new < trigger -> FN1, LR1 (and W1-W3) fail; letters only, no digits -> P5 fails; drop the ordered marker test -> LM9, LM10, S2, S4 fail; require a blank after the ordered marker -> S2, S4 fail; drop the pipe test -> P3 fails; indent test always true -> B1, L1 fail; drop the trailing trim -> CR1, S4 fail; old < trigger (3 columns, no markers) -> HL1, HL2 fail; markers but 3 columns only -> HL2 fails; any indent but no markers -> HL1 fails; no sticky < test, or clearing it at a blank line -> HP1, HP2, HL1, HL2 fail; flush the run joined under a delimiter row -> D1, D2, D5, D7, D8, CR1 (and D3, D4) fail; split only a run of two lines -> D8 fails; require : or | in the delimiter row -> D3, D4 fail; reset at a fence end -> FR1 fails; let a plain line join after a non-plain one -> T2, G5-G7, G15, G16 and the S pins fail; no reset at a blank line -> T4 fails; no flush at a blank line -> R1 fails, before a fence -> R3 fails; no one-break limit -> R2 fails; never join -> P1, P4, P5, T4 fail. Survivor: dropping the quote marker (>) from the < trigger changes nothing (exit 0): an HTML block inside a block quote ends at the first line without >, and every quoted line is already not plain. The fence-end reset is now killed only by the over-lint pin FR1: the sticky < test covers every fence-inside-HTML case, so that clause guards no fail-open on its own.
