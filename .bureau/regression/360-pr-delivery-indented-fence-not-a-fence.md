name: pr-delivery.sh placeholder strip opens a fence only at 3 columns or less; a ``` line at 4+ columns opens nothing, a closer closes at any indent, the body before a 4+ column closer is linted, and after a 4+ column fence line no fence opens; a CR (leading, mid-line or CRLF) ends a line
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
  # L2: L1 followed by a top-level indented ``` line (I1). Main a2d4029 opens a fence there
  # and hides the placeholder GitHub shows.
  printf 'text\n\n- item\n\n  ```\n  code\n    ```\n\ntext\n\n    ```\n\nreal placeholder <fill me>\n\n```sh\ncode\n```\n' > "$T/in.md"
  visible "L2 list-item closer, then an indented fence-like line" '<fill me>'
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
  # O3: O1 after a top-level indented ``` line (I1), which flips the fences main a2d4029
  # sees, so it hides the placeholder GitHub shows.
  printf 'text\n\n    ```\n\n- item\n\n    ```\n    code\n  ```\nreal placeholder <fill me>\n```\nmore\n```\n' > "$T/in.md"
  visible "O3 indented fence-like line, then a list-item opener" '<fill me>'
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
  # CR1: a bare CR is a line ending (CommonMark), so a CR then ``` is a closer at column 0
  # on GitHub; the placeholder after it is plain text. Main a2d4029 closed it too.
  printf '```\ncode\n\r```\nreal placeholder <fill me>\n```\nmore\n' > "$T/in.md"
  visible "CR1 closer after a bare CR" '<fill me>'
  # CR2: the same for an opener; skipping it would flip which later ``` open and close.
  printf '\r```\ncode <a>\n```\nreal placeholder <fill me>\n```\nmore\n```\n' > "$T/in.md"
  visible "CR2 opener after a bare CR" '<fill me>'
  # CR3: the indent counts from the last CR, so spaces before it do not make a 4+ column
  # opener; the fence opens and closes as on GitHub (and main).
  printf 'text\n\n    \r```\n<k>\n```\n\nafter\n' > "$T/in.md"
  hidden "CR3 indent counts from the last CR" '<k>'
  # CR5: any whitespace before the CR (a form feed, a vertical tab) belongs to the line
  # before it, so the ``` after the CR still closes the fence.
  printf '```\ncode\n\f\r```\nreal placeholder <fill me>\n```\nmore\n' > "$T/in.md"
  visible "CR5 closer after a form feed and a CR" '<fill me>'
  printf '\v\r```\ncode <a>\n```\nreal placeholder <fill me>\n```\nmore\n```\n' > "$T/in.md"
  visible "CR5 opener after a vertical tab and a CR" '<fill me>'
  # CR4: CRLF line endings open and close fences as LF does.
  printf 'text\r\n\r\n```\r\n<k>\r\n```\r\nreal placeholder <fill me>\r\n' > "$T/in.md"
  hidden "CR4 CRLF fence body" '<k>'
  visible "CR4 CRLF text after the fence" '<fill me>'
  # CR6: a CR mid-line ends the line too, so a ``` after it closes the fence; the
  # placeholder after it is plain text on GitHub.
  printf '```\ncode\r```\nreal placeholder <fill me>\n```\nmore\n' > "$T/in.md"
  visible "CR6 closer after a mid-line CR" '<fill me>'
  # CR7: the closer and the placeholder on one physical line, split by CRs.
  printf '```\ncode\r```\r<fill me> after\n```\nx\n```\n' > "$T/in.md"
  visible "CR7 closer and text after it on one physical line" '<fill me>'
  # CR8: a CR inside a placeholder on a line after a mid-line closer: GitHub shows it as
  # paragraph text, and the stripped text keeps it on one line, so the lint regex
  # cmd_ready uses still matches it.
  printf '```\ncode\r```\na <fill\rme> b\n```\nmore\n' > "$T/in.md"
  strip "CR8 placeholder split by a CR"
  grep -Eq '<[^>]+>' "$T/out" || { echo "FAIL: CR8: placeholder split by a CR is not linted"; od -c "$T/out"; exit 1; }
  # CR9: a list item ends inside its fence (opener at two columns after a CR) and the
  # closer at column 0 follows a mid-line CR; GitHub shows the placeholder as plain text.
  # The CR-split pass hides it, as the strip does for the same file with LF line ends; the
  # pass over whole LF lines (run for any file with a CR) and the main pass still lint it.
  printf 'text\n\n- item\n\r  ```\n  code\n\nreal placeholder <fill me>\r```\n\nafter\n' > "$T/in.md"
  visible "CR9 list fence closed after a mid-line CR" '<fill me>'
  # CR10: CR9 with a 4-column ``` line after it. Main a2d4029 closes its fence there and
  # hides the placeholder, as does the CR-split pass; GitHub shows it, and only the pass
  # over whole LF lines lints it.
  printf 'text\n\n- item\n\r  ```\n  code\n\nreal placeholder <fill me>\r```\n\n    ```\n\nafter\n' > "$T/in.md"
  visible "CR10 list fence closed after a mid-line CR, indented fence line after" '<fill me>'
  # M1, M2: an HTML block holding a 4-column fence-like line. GitHub shows <real> as raw
  # HTML. Main a2d4029 opens a fence that never closes and dumps it raw; here that line
  # opens nothing and the span below is stripped (the tilde line leaves no backtick
  # unmatched in M1, the blank line ends the raw print in M2), so only the pass that runs
  # main parse keeps <real> (red on 92ad0e6).
  printf '<div>\n    ~~~\n`code <real>`\n</div>\n' > "$T/in.md"
  visible "M1 tilde line in an HTML block" '<real>'
  printf '<pre>\n    ```\n\n`code <real>`\n</pre>\n' > "$T/in.md"
  visible "M2 backtick line and a blank line in <pre>" '<real>'
  echo PASS
expected: exit 0; stdout "PASS". A ``` line indented four or more columns (four spaces I1, a tab I2, two spaces and a tab I3) opens no fence, so a later placeholder before the next real fence stays visible to the lint. A closer at any indent closes an open fence. A fence line at four or more columns is ambiguous (a list item's fence line on GitHub, L1 closer, O1 and O2 openers; code at top level, R1), so after it no fence opens and every later line is linted (L1, L2, O1-O3, R1, R2 visible; I4 is an over-lint pin). The body of a fence closed by an ambiguous closer is linted, not dropped, because a list item can end inside it (E1 visible; A1 is an over-lint pin). A fence indented three spaces still opens and closes (C1). A bare CR is a line ending, so a ``` after a CR in the leading whitespace is a fence line whose indent counts from that CR: it closes (CR1) and opens (CR2) a fence, spaces before the CR do not make it a 4+ column line (CR3, hidden), and neither does a form feed or vertical tab before the CR (CR5, closer and opener); CRLF files open and close fences as LF does (CR4). A CR mid-line ends the line too, so a ``` after it closes the fence and the placeholder after it, on the next line (CR6) or the same physical line (CR7), is linted. A placeholder split by a CR outside a fence still matches the lint regex (CR8). A file holding a CR is also parsed as whole LF lines and that output is linted too, so a placeholder GitHub shows after a list item ends inside a fence closed at column 0 after a mid-line CR (CR9) is linted though the CR-split parse hides it, as the strip does for the same file with LF line ends (over-lint, fail-safe: fence bodies in a file with mid-line CRs are linted); CR10 is the same shape where main a2d4029 hides the placeholder too. The parse of main a2d4029 also runs on every file and its output is linted: M1 and M2, an HTML block holding a 4-column fence-like line, whose placeholder GitHub shows and only that pass prints (both red on 92ad0e6). That pass also shows L1, O1, O2, CR1, CR2 and CR9, so the rows that pin the other passes are the ones main hides. Mutations (on copies of scripts/pr-delivery.sh, every row run): drop the column test on the opener (open at any indent) and I1-I3 fail; restore `col <= 3` on the closer and L2 fails; drop the `!amb` test on the opener and R1, R2 and O3 fail; stop a 4+ column opener setting amb and O3 fails; stop a 4+ column closer setting amb and R1 and R2 fail; drop the body at an ambiguous closer again and E1, A1 and CR10 fail; stop splitting lines on CR in the first pass and CR3, CR6, CR7 and CR8 fail; print the CR-split pieces of a line on separate lines and CR8 fails; drop the whole-LF-line pass and CR10 fails; drop the last-CR indent scan in that pass and CR3 fails; drop the main pass and M1 and M2 fail; count columns in the main pass as the others do and CR3, M1 and M2 fail; strip only spaces and tabs from its lead and CR3 fails.
