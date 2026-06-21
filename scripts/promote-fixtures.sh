#!/bin/sh
# Deterministic mechanical core of Bureau fixture promotion: skip <none> →
# refuse non-repo-relative → dedupe by slug + command:/expected: content →
# copy survivors verbatim into <repo>/.bureau/regression/ → run suite green.
#
# Usage:
#   sh scripts/promote-fixtures.sh --src <dir> --repo <dir> [--only <slug,...>] [--apply]
#
# Args:
#   --src <dir>           Required. Scratch fixture dir for this run (RUN_DIR/regression/).
#   --repo <dir>          Required. Target repo root whose .bureau/regression/ is the promoted home.
#   --only <slug,...>     Optional. Comma-separated fixture slugs (without .md) to process.
#                         Omit to process all NN-*.md files in --src.
#   --apply               Optional. Without it, dry-run: report decisions, write nothing, run no suite.
#
# Exit codes:
#   0  Survivors copied and suite green (or dry-run with no clash).
#   2  Setup error: bad args, --src or --repo missing or not a dir, no run.sh in target repo.
#   3  Dedupe content clash (same slug, different command:/expected:) — [CHECKPOINT];
#      nothing copied past the clash; Conductor resolves. Report names every already-copied slug.
#   4  Suite non-green after copy; Conductor must NOT commit; investigate failing fixture.
#
# DOES NOT mutation-test (mutation-test is an authoring-convention obligation, not a script gate).
# DOES NOT repath (repo-relative is an authoring-time guarantee per docs/conventions.md).
# NEVER commits (commit is a Conductor action gated on exit 0).
# NEVER pushes (push is past the production boundary; always the human's call).
#
# Convention: docs/conventions.md § Regression fixture file format
# Promotion lifecycle: workflows/execute-plan.md § step 7

set -u

# ── helpers ──────────────────────────────────────────────────────────────────

die() { printf 'promote-fixtures: %s\n' "$*" >&2; exit 2; }

# Extract the full command: body from a fixture file.
# Handles both inline ("command: value") and block-literal ("command: |") forms.
# Same awk logic as .bureau/regression/run.sh.
extract_cmd() {
  awk '
    /^command:[[:space:]]*\|[[:space:]]*$/ { blk = 1; next }
    blk == 1 {
      if ($0 ~ /^[[:space:]]/ || $0 == "") { sub(/^  /, ""); print; next }
      blk = 0
    }
    /^command:[[:space:]]*[^|]/ && got != 1 { sub(/^command:[[:space:]]*/, ""); print; got = 1 }
  ' "$1"
}

# Extract the expected: field value (single line after "expected: ").
extract_expected() {
  awk '/^expected:[[:space:]]/ && got != 1 { sub(/^expected:[[:space:]]*/, ""); print; got = 1 }' "$1"
}

# Returns 0 if slug is present in comma-separated list, 1 otherwise.
slug_in_list() {
  _sil_slug="$1"
  _sil_list="$2"
  # Wrap list with commas so every slug is bounded; grep -F for literal match.
  printf ',%s,' "$_sil_list" | grep -qF ",${_sil_slug},"
}

# ── argument parsing ─────────────────────────────────────────────────────────

SRC=""
REPO=""
ONLY=""
APPLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --src)
      [ $# -ge 2 ] || die "--src requires a value"
      SRC="$2"; shift 2 ;;
    --repo)
      [ $# -ge 2 ] || die "--repo requires a value"
      REPO="$2"; shift 2 ;;
    --only)
      [ $# -ge 2 ] || die "--only requires a value"
      ONLY="$2"; shift 2 ;;
    --apply)
      APPLY=1; shift ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      die "unknown argument: $1" ;;
  esac
done

# ── setup validation (exit 2) ────────────────────────────────────────────────

[ -n "$SRC" ]  || die "--src is required"
[ -n "$REPO" ] || die "--repo is required"
[ -d "$SRC" ]  || die "--src dir does not exist or is not a directory: $SRC"
[ -d "$REPO" ] || die "--repo dir does not exist or is not a directory: $REPO"

RUNNER="$REPO/.bureau/regression/run.sh"
[ -f "$RUNNER" ] || die "no run.sh found at $REPO/.bureau/regression/run.sh"

DEST="$REPO/.bureau/regression"

if [ "$APPLY" -eq 0 ]; then
  printf 'promote-fixtures: dry-run (no --apply; nothing will be written or run)\n'
fi

# ── build sorted candidate list (temp file for POSIX-safe sorted iteration) ──

# Use a temp file to hold sorted slug names; avoids unquoted word-split on a variable.
_cand_tmp=$(mktemp "${TMPDIR:-/tmp}/promote-fixtures.cand.XXXXXX")
trap 'rm -f "$_cand_tmp"' EXIT

for f in "$SRC"/[0-9][0-9]-*.md; do
  [ -f "$f" ] || continue
  slug=$(basename "$f" .md)
  if [ -n "$ONLY" ]; then
    slug_in_list "$slug" "$ONLY" || continue
  fi
  printf '%s\n' "$slug" >> "$_cand_tmp"
done

# Sort in place (lexical, same order as runner glob).
# Use a second temp and mv to avoid reading/writing the same file.
_sorted_tmp=$(mktemp "${TMPDIR:-/tmp}/promote-fixtures.sorted.XXXXXX")
trap 'rm -f "$_cand_tmp" "$_sorted_tmp"' EXIT
sort "$_cand_tmp" > "$_sorted_tmp"

# ── per-fixture pipeline ─────────────────────────────────────────────────────

# Track copied slugs in a temp file (one slug per line) for CLASH report.
_copied_tmp=$(mktemp "${TMPDIR:-/tmp}/promote-fixtures.copied.XXXXXX")
trap 'rm -f "$_cand_tmp" "$_sorted_tmp" "$_copied_tmp"' EXIT

while IFS= read -r slug; do
  [ -n "$slug" ] || continue
  src_file="$SRC/${slug}.md"
  dest_file="$DEST/${slug}.md"

  # ── 1. Skip <none> ──────────────────────────────────────────────────────
  # Trigger ONLY when the command: VALUE is EXACTLY the sentinel string.
  # For a block-literal command, the awk extractor returns the full block body.
  # For a single-line value that IS exactly the sentinel, cmd_trimmed equals it.
  # A heredoc inside a conformant block that merely mentions the sentinel is NOT skipped
  # (the full block body would not equal the sentinel string).
  cmd=$(extract_cmd "$src_file")
  cmd_trimmed=$(printf '%s' "$cmd" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  if [ "$cmd_trimmed" = '<none — phase accepted on visual inspection>' ]; then
    printf 'SKIP none              %s\n' "$slug"
    continue
  fi

  # ── 2. Refuse non-repo-relative ─────────────────────────────────────────
  # Refuse if the command: body LACKS the anchor substring.
  # Conformant fixtures that HAVE the anchor are not refused even if their body
  # also mentions $RUN_DIR or an absolute path as test data inside a heredoc.
  # The check is solely: does the command: body contain the anchor?
  # SC2016: single-quoted pattern is intentional — we want the literal string.
  # shellcheck disable=SC2016
  case "$cmd" in
    *'ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"'*)
      # Anchor present — conformant, fall through.
      ;;
    *)
      printf 'SKIP not-repo-relative %s\n' "$slug"
      continue
      ;;
  esac

  # ── 3. Dedupe by slug + content ─────────────────────────────────────────
  if [ -f "$dest_file" ]; then
    incoming_cmd=$(extract_cmd "$src_file")
    incoming_exp=$(extract_expected "$src_file")
    existing_cmd=$(extract_cmd "$dest_file")
    existing_exp=$(extract_expected "$dest_file")

    if [ "$incoming_cmd" = "$existing_cmd" ] && [ "$incoming_exp" = "$existing_exp" ]; then
      printf 'SKIP identical         %s\n' "$slug"
      continue
    else
      # Content clash — report every already-copied slug and exit 3.
      printf 'CLASH                  %s\n' "$slug"
      printf '  command: or expected: differs from existing .bureau/regression/%s.md\n' "$slug"
      if [ -s "$_copied_tmp" ]; then
        printf '  already copied this run:'
        while IFS= read -r cs; do printf ' %s' "$cs"; done < "$_copied_tmp"
        printf '\n'
      else
        printf '  already copied this run: (none)\n'
      fi
      printf '  [CHECKPOINT] Conductor must resolve before proceeding.\n'
      exit 3
    fi
  fi

  # ── 4. Copy verbatim (only under --apply) ───────────────────────────────
  if [ "$APPLY" -eq 1 ]; then
    cp "$src_file" "$dest_file"
    printf 'COPY                   %s\n' "$slug"
    printf '%s\n' "$slug" >> "$_copied_tmp"
  else
    printf 'COPY (dry-run)         %s\n' "$slug"
  fi

done < "$_sorted_tmp"

# ── 5. Run the suite (only under --apply, after all survivors are copied) ────

if [ "$APPLY" -eq 1 ]; then
  if [ -s "$_copied_tmp" ]; then
    printf 'promote-fixtures: running suite: sh %s\n' "$RUNNER"
    if sh "$RUNNER"; then
      printf 'promote-fixtures: suite green — exit 0\n'
    else
      printf 'SUITE FAILED — one or more fixtures failed; Conductor must NOT commit\n' >&2
      exit 4
    fi
  else
    printf 'promote-fixtures: no new fixtures copied; skipping suite run\n'
  fi
fi

exit 0
