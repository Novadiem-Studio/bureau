#!/usr/bin/env bash
# link-set-check.sh — verify a revised candidate kept every markdown link target of the draft.
#
# Usage:
#   link-set-check.sh <draft-file> <candidate-file>
#
# Exit codes:
#   0  every link target `](target)` present in <draft-file> also appears in <candidate-file>
#   3  one or more targets are missing (listed on stderr, one per line)
#   1  bad arguments / unreadable file
#
# Why: the "improve" cross-model pass is told not to remove links, but a model can convert links
# to plain text while staying inside the byte-ratio integrity bound, so the loss is invisible to
# model-pass.sh and only surfaces when the target build fails a link floor (observed 2026-09-06,
# devweb topic-overviews run: 2 of 3 candidates dropped every glossary and hub link). Targets
# are compared as a set; link TEXT may change, position may change, duplicates collapse.
# Bash 3.2 / macOS portable.

set -euo pipefail

[ "$#" -eq 2 ] || { echo "Usage: link-set-check.sh <draft-file> <candidate-file>" >&2; exit 1; }
DRAFT="$1"; CANDIDATE="$2"
[ -r "$DRAFT" ]     || { echo "link-set-check: cannot read draft: $DRAFT" >&2; exit 1; }
[ -r "$CANDIDATE" ] || { echo "link-set-check: cannot read candidate: $CANDIDATE" >&2; exit 1; }

# Inline markdown link targets only: `](target)`. Reference-style links and bare URLs are out of
# scope; the passes this guards produce inline links.
extract_targets() {
  { grep -oE '\]\([^)[:space:]]+\)' "$1" || true; } | sed -E 's/^\]\(//; s/\)$//' | LC_ALL=C sort -u
}

DRAFT_TARGETS="$(extract_targets "$DRAFT")"
[ -n "$DRAFT_TARGETS" ] || exit 0   # a draft with no links has nothing to lose

CANDIDATE_TARGETS="$(extract_targets "$CANDIDATE")"
MISSING="$(LC_ALL=C comm -23 <(printf '%s\n' "$DRAFT_TARGETS") <(printf '%s\n' "$CANDIDATE_TARGETS"))"

if [ -n "$MISSING" ]; then
  COUNT="$(printf '%s\n' "$MISSING" | wc -l | tr -d '[:space:]')"
  echo "link-set-check: $COUNT link target(s) in the draft are missing from the candidate:" >&2
  printf '%s\n' "$MISSING" | sed 's/^/  /' >&2
  exit 3
fi
exit 0
