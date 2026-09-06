#!/usr/bin/env python3
"""check-numbers.py — every number in a page must trace to the dataset tables it was written from.

Usage: check-numbers.py <page.mdx> <tables.md> [<more-source.md> ...]
Exit 0 when every numeric token in the page body appears (as a token) in at least one source file;
exit 3 listing the orphans otherwise; exit 1 on bad arguments.

What counts as a number: any token with a digit, after stripping $ , % ~ and trailing punctuation
(e.g. "$24.64", "27,804,254", "95%", "~6,950", "2026-09-06"). Ignored on purpose: frontmatter,
markdown link targets and URLs, inline/fenced code, small counts 0–12 (written as words or as list
structure, not data), and bare years 2024–2027. A number written differently from the table
("24.6" for 24.64, "27.8 million" for 27,804,254) IS an orphan: the writer copies figures, never
rounds or reformats them, so the reader can find every figure in the table.
"""
import re, sys

def body_without_frontmatter(text):
    if text.startswith('---'):
        parts = text.split('\n---', 2)
        if len(parts) >= 3:
            return parts[2]
    return text

def strip_noise(text):
    text = re.sub(r'```.*?```', ' ', text, flags=re.S)          # fenced code
    text = re.sub(r'`[^`]*`', ' ', text)                          # inline code
    text = re.sub(r'\]\([^)]*\)', ']', text)                      # link targets
    text = re.sub(r'https?://\S+', ' ', text)                     # bare URLs
    return text

TOKEN = re.compile(r'[~$]?\d[\d,]*(?:\.\d+)?%?')

def numbers(text):
    out = set()
    for m in TOKEN.finditer(text):
        tok = m.group(0).strip('~$%').rstrip('.,')
        if not tok or not re.search(r'\d', tok):
            continue
        norm = tok.replace(',', '')
        out.add(norm)
    return out

def main():
    if len(sys.argv) < 3:
        print(__doc__.strip().splitlines()[2]); sys.exit(1)
    page = strip_noise(body_without_frontmatter(open(sys.argv[1], errors='ignore').read()))
    sources = set()
    for src in sys.argv[2:]:
        sources |= numbers(open(src, errors='ignore').read())
    # also accept the source numbers without their decimals' trailing zeros and with common thousands forms
    accept = set(sources)
    for s in sources:
        try:
            f = float(s)
            accept.add(('%f' % f).rstrip('0').rstrip('.'))
            if f == int(f): accept.add(str(int(f)))
        except ValueError:
            pass
    orphans = []
    for n in sorted(numbers(page), key=lambda x: (len(x), x)):
        try:
            f = float(n)
        except ValueError:
            # dates like 2026-09-06 arrive as "2026-09-06"? TOKEN splits on '-', so no; keep as-is
            f = None
        if f is not None and f == int(f) and 0 <= int(f) <= 12:
            continue                                   # small counts / list numbers
        if f is not None and f == int(f) and 2024 <= int(f) <= 2027:
            continue                                   # bare years
        if n in accept:
            continue
        orphans.append(n)
    if orphans:
        print(f"check-numbers: {len(orphans)} number(s) in the page do not appear in the dataset tables:", file=sys.stderr)
        for o in orphans:
            print(f"  {o}", file=sys.stderr)
        sys.exit(3)
    print(f"check-numbers: OK — every number in the page traces to the tables ({len(numbers(page))} checked)")

if __name__ == '__main__':
    main()
