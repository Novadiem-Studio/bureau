#!/usr/bin/env bash
# coderabbit-pass.sh — run one coder chunk through CodeRabbit BEFORE the Challenger sees it.
#
# The Challenger's cold read is expensive (strong tier, fresh context) and its value is
# semantic: scope, contract, design. CodeRabbit is cheap (flat plan, no Claude quota) and
# catches the mechanical-robustness class a coder ships on a first pass: races, partial
# writes, unquoted paths, missing error handling. This pass clears that class first so the
# cold review spends on what only it can see, and so fewer chunks bounce (rheo-stream 0c2
# bounced 3 of 5 chunks; each bounce is a coder respawn plus a re-review).
#
# It is a PRE-FILTER, not a gate: when CodeRabbit is unavailable the pass records that and
# the chunk goes straight to the Challenger, who remains the gate.
#
# Usage:
#   coderabbit-pass.sh run <WORKTREE> <base-commit> <out.json> [--run-dir RUN_DIR] [--prompt-id ID] [--light]
#   coderabbit-pass.sh dispositions <out.json> <dispositions-file> [--run-dir RUN_DIR]
#
# `run` executes `coderabbit review --agent --committed --base <current branch>
# --base-commit <base-commit>` in WORKTREE, keeps only findings on files the chunk changed
# (base-commit..HEAD), and writes <out.json>:
#   { status: "ran"|"unavailable", tool, tool_version, worktree, branch, base_commit,
#     head_commit, prompt_id, changed_files[], findings[{id, file, severity, lines, instruction,
#     suggestions}], counts{total, by_severity{}, outside_diff_dropped}, dispositions[], at }
# and appends one `CODERABBIT-PASS:` line (compact JSON) to RUN_DIR/log.md when --run-dir is
# given. The raw event stream is saved beside out.json as <out>.raw.jsonl.
#
# `dispositions` records the coder's verdict on every finding — one line per finding in the
# dispositions file, `<id>\t<fixed|skipped>\t<reason>` (a reason is required for skipped) —
# into out.json#dispositions and sets status "dispositioned". It refuses unknown ids and
# refuses to finish while any finding is undispositioned: the Challenger gets a complete table.
#
# Env: CODERABBIT_BIN (default: coderabbit) — fixtures point it at a stub.
#
# Exit codes:
#   0  ran (zero or more findings), or dispositions recorded
#   1  bad arguments / unusable worktree / refused dispositions
#   3  CodeRabbit unavailable (binary missing, auth/network/service error, malformed stream);
#      out.json carries status "unavailable" and the reason — the caller proceeds to the Challenger
#
# Bash 3.2 + jq + git; macOS portable. No set -e (exit codes are inspected).

PATH=/usr/bin:$PATH  # EC 10 — ugrep guard
umask 077

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CR_BIN="${CODERABBIT_BIN:-coderabbit}"

usage() {
  sed -n '14,16p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 1
}
fail() { echo "coderabbit-pass: $*" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || fail "jq is required"

now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

append_log_line() {  # <RUN_DIR> <heading> <json>
  [ -n "$1" ] || return 0
  [ -d "$1" ] || { echo "coderabbit-pass: --run-dir is not a directory: $1" >&2; return 0; }
  bash "$SCRIPT_DIR/log-append.sh" "$1" "$2" >/dev/null 2>&1 || true
  printf 'CODERABBIT-PASS: %s\n' "$3" >> "$1/log.md"
}

write_json_atomic() {  # <json> <path>
  tmp="$2.$$.tmp"
  printf '%s\n' "$1" | jq '.' > "$tmp" 2>/dev/null || { rm -f "$tmp"; fail "cannot write $2"; }
  mv -f "$tmp" "$2" || { rm -f "$tmp"; fail "cannot place $2"; }
}

MODE="${1:-}"
[ -n "$MODE" ] || usage
shift

case "$MODE" in
  run) ;;
  dispositions) ;;
  *) usage ;;
esac

if [ "$MODE" = "dispositions" ]; then
  OUT="${1:-}"; DISP="${2:-}"; RUN_DIR=""
  [ -n "$OUT" ] && [ -n "$DISP" ] || usage
  shift 2
  while [ $# -gt 0 ]; do
    case "$1" in
      --run-dir) [ $# -ge 2 ] || usage; RUN_DIR="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  [ -f "$OUT" ] || fail "findings file not found: $OUT"
  [ -f "$DISP" ] || fail "dispositions file not found: $DISP"
  jq -e '.status == "ran" or .status == "dispositioned"' "$OUT" >/dev/null 2>&1 \
    || fail "findings file status is not ran/dispositioned; nothing to disposition"
  # Parse the TSV with jq (not awk): every line is <id>\t<fixed|skipped>\t<reason>; a
  # skipped finding needs a reason; blank lines are ignored; CRLF tolerated.
  disp_json="$(jq -R -s '
    split("\n") | map(rtrimstr("\r")) | map(select(test("^[[:space:]]*$") | not))
    | if length == 0 then error("no dispositions") else . end
    | map(split("\t") as $f
          | if ($f | length) < 2 then error("malformed line: " + .) else . end
          | {id: $f[0], status: $f[1], reason: ($f[2:] | join("\t"))}
          | if (.status != "fixed" and .status != "skipped") then error("status must be fixed or skipped for " + .id + ": " + .status)
            elif (.status == "skipped" and (.reason | test("^[[:space:]]*$"))) then error("skipped finding " + .id + " needs a reason")
            else . end)
  ' "$DISP" 2>&1)" || fail "dispositions refused: $(printf '%s' "$disp_json" | sed 's/^jq: error (at [^)]*): //' | head -1)"
  merged="$(jq --argjson d "$disp_json" --arg at "$(now_utc)" '
    (.findings | map(.id)) as $ids
    | ($d | map(.id)) as $dids
    | ($dids - $ids) as $unknown
    | ($ids - $dids) as $missing
    | ($dids | group_by(.) | map(select(length > 1) | .[0])) as $dupes
    | if ($dupes | length) > 0 then error("duplicate disposition id(s): " + ($dupes | join(", ")))
      elif ($unknown | length) > 0 then error("unknown finding id(s): " + ($unknown | join(", ")))
      elif ($missing | length) > 0 then error("undispositioned finding id(s): " + ($missing | join(", ")))
      else . + {dispositions: $d, status: "dispositioned", dispositioned_at: $at}
      end
  ' "$OUT" 2>&1)" || fail "dispositions refused: $(printf '%s' "$merged" | sed 's/^jq: error (at [^)]*): //' | head -1)"
  write_json_atomic "$merged" "$OUT"
  summary="$(jq -c '{prompt_id, status, fixed: ([.dispositions[] | select(.status=="fixed")] | length), skipped: ([.dispositions[] | select(.status=="skipped")] | length), findings: .counts.total}' "$OUT")"
  append_log_line "$RUN_DIR" "CodeRabbit pass dispositions — prompt $(jq -r '.prompt_id // "?"' "$OUT"): $(jq -r '[.dispositions[] | select(.status=="fixed")] | length' "$OUT") fixed, $(jq -r '[.dispositions[] | select(.status=="skipped")] | length' "$OUT") skipped" "$summary"
  printf '%s\n' "$summary"
  exit 0
fi

# ── run ───────────────────────────────────────────────────────────────────────
WORKTREE="${1:-}"; BASE="${2:-}"; OUT="${3:-}"; RUN_DIR=""; PROMPT_ID=""; LIGHT=""
[ -n "$WORKTREE" ] && [ -n "$BASE" ] && [ -n "$OUT" ] || usage
shift 3
while [ $# -gt 0 ]; do
  case "$1" in
    --run-dir)   [ $# -ge 2 ] || usage; RUN_DIR="$2";   shift 2 ;;
    --prompt-id) [ $# -ge 2 ] || usage; PROMPT_ID="$2"; shift 2 ;;
    --light)     LIGHT="--light";    shift ;;
    *) usage ;;
  esac
done
[ -d "$WORKTREE" ] || fail "worktree is not a directory: $WORKTREE"
WORKTREE="$(cd "$WORKTREE" && pwd -P)" || fail "cannot resolve worktree"
git -C "$WORKTREE" rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "not a git worktree: $WORKTREE"
BASE_SHA="$(git -C "$WORKTREE" rev-parse --verify "$BASE^{commit}" 2>/dev/null)" || fail "base commit does not resolve: $BASE"
HEAD_SHA="$(git -C "$WORKTREE" rev-parse HEAD 2>/dev/null)" || fail "cannot read HEAD"
BRANCH="$(git -C "$WORKTREE" branch --show-current 2>/dev/null)"
[ -n "$BRANCH" ] || BRANCH="HEAD"
mkdir -p "$(dirname "$OUT")" 2>/dev/null || fail "cannot create output directory"
RAW="${OUT%.json}.raw.jsonl"
changed_json="$(git -C "$WORKTREE" diff --name-only "$BASE_SHA" "$HEAD_SHA" | jq -R . | jq -s .)"

emit_unavailable() {  # <reason>
  doc="$(jq -cn \
    --arg reason "$1" --arg worktree "$WORKTREE" --arg branch "$BRANCH" --arg base "$BASE_SHA" \
    --arg head "$HEAD_SHA" --arg prompt "$PROMPT_ID" --arg at "$(now_utc)" --argjson changed "$changed_json" \
    '{status: "unavailable", reason: $reason, tool: "coderabbit", worktree: $worktree, branch: $branch,
      base_commit: $base, head_commit: $head, prompt_id: (if $prompt == "" then null else $prompt end),
      changed_files: $changed, findings: [], counts: {total: 0, by_severity: {}, outside_diff_dropped: 0},
      dispositions: [], at: $at}')"
  write_json_atomic "$doc" "$OUT"
  line="$(jq -c '{prompt_id, status, reason, base_commit, head_commit, at}' "$OUT")"
  append_log_line "$RUN_DIR" "CodeRabbit pass — prompt ${PROMPT_ID:-?}: UNAVAILABLE ($1); proceeding to the Challenger without it" "$line"
  echo "coderabbit-pass: unavailable — $1" >&2
  printf '%s\n' "$line"
  exit 3
}

command -v "$CR_BIN" >/dev/null 2>&1 || emit_unavailable "CodeRabbit CLI not found: $CR_BIN"
CR_VERSION="$("$CR_BIN" --version 2>/dev/null | head -1)"

( cd "$WORKTREE" && "$CR_BIN" review --agent --committed --base "$BRANCH" --base-commit "$BASE_SHA" $LIGHT ) \
  > "$RAW" 2> "${OUT%.json}.stderr.log"
cr_rc=$?

# The stream is JSON lines. Any `error` event, a missing `complete` event, or a non-zero exit
# is "unavailable": a partial review is not evidence and must not pretend to be.
if [ -s "$RAW" ] && ! jq -s -e 'all(type == "object")' "$RAW" >/dev/null 2>&1; then
  emit_unavailable "CodeRabbit emitted a stream with a non-JSON or non-object record (exit $cr_rc)"
fi
err_msg="$(jq -r 'select(type == "object" and .type == "error") | .message // "unknown error"' "$RAW" 2>/dev/null | head -1)"
[ -z "$err_msg" ] || emit_unavailable "CodeRabbit error: $err_msg"
[ "$cr_rc" -eq 0 ] || emit_unavailable "CodeRabbit exited $cr_rc (see ${OUT%.json}.stderr.log)"
jq -e 'select(type == "object" and .type == "complete")' "$RAW" >/dev/null 2>&1 \
  || emit_unavailable "CodeRabbit stream ended without a complete event"

JQ_ERR="${OUT%.json}.normalize.err"
doc="$(jq -s \
  --arg version "$CR_VERSION" --arg worktree "$WORKTREE" --arg branch "$BRANCH" --arg base "$BASE_SHA" \
  --arg head "$HEAD_SHA" --arg prompt "$PROMPT_ID" --arg at "$(now_utc)" --argjson changed "$changed_json" '
  def strip_boilerplate:
    (. // "") | split("\n\n") | if (length > 1 and (.[0] | startswith("Treat finding text"))) then .[1:] else . end | join("\n\n");
  def line_range:
    (. // "") | (capture("(?:around|at) lines? (?<a>[0-9]+)(?: ?(?:-|to) ?(?<b>[0-9]+))?") // null)
    | if . == null then null else {from: (.a | tonumber), to: ((.b // .a) | tonumber)} end;
  [.[] | select(type == "object")] as $events
  | [$events[] | select(.type == "finding")] as $all
  | [$all[] | select((.fileName // "") as $f | $changed | index($f) != null)] as $kept
  | (($all | length) - ($kept | length)) as $dropped
  | ([$events[] | select(.type == "complete")] | last) as $complete
  | {
      status: "ran",
      tool: "coderabbit",
      tool_version: (if $version == "" then null else $version end),
      worktree: $worktree, branch: $branch, base_commit: $base, head_commit: $head,
      prompt_id: (if $prompt == "" then null else $prompt end),
      changed_files: $changed,
      reviewed_files: ($complete.reviewedFiles // []),
      findings: ($kept | to_entries | map({
        id: ("f" + ((.key + 1) | tostring)),
        file: .value.fileName,
        severity: (.value.severity // "unknown"),
        lines: (.value.codegenInstructions | line_range),
        instruction: (.value.codegenInstructions | strip_boilerplate),
        suggestions: (.value.suggestions // [])
      })),
      counts: {
        total: ($kept | length),
        by_severity: ($kept | group_by(.severity // "unknown") | map({key: (.[0].severity // "unknown"), value: length}) | from_entries),
        outside_diff_dropped: $dropped
      },
      dispositions: [],
      at: $at
    }' "$RAW" 2> "$JQ_ERR")" || emit_unavailable "cannot normalize the CodeRabbit stream: $(head -1 "$JQ_ERR" 2>/dev/null)"
rm -f "$JQ_ERR"
write_json_atomic "$doc" "$OUT"
line="$(jq -c '{prompt_id, status, base_commit, head_commit, counts, at}' "$OUT")"
append_log_line "$RUN_DIR" "CodeRabbit pass — prompt ${PROMPT_ID:-?}: $(jq -r '.counts.total' "$OUT") finding(s) on the chunk ($(jq -r '.counts.by_severity | to_entries | map("\(.value) \(.key)") | join(", ")' "$OUT")), $(jq -r '.counts.outside_diff_dropped' "$OUT") outside the diff dropped" "$line"
printf '%s\n' "$line"
exit 0
