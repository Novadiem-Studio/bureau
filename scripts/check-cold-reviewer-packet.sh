#!/usr/bin/env bash
# check-cold-reviewer-packet.sh — self-test for run-cold-reviewer.sh's packet contract (#79).
#
# Stages a two-artifact packet (plan.md primary, spec.md supplementary) in a temp dir
# and runs run-cold-reviewer.sh against stub reviewer CLIs, one per host. It fails if:
#   - any host's task prompt does not name spec.md with its digest,
#   - artifacts.sha256 does not list both artifacts, primary first,
#   - a verdict whose Artifacts-read skips spec.md is reported as complete,
#   - a verdict with no Artifacts-read at all is accepted,
#   - a verdict naming an artifact outside the manifest is reported as complete,
#   - a Cursor resume is accepted after the packet changed since the plan,
#   - the v1 watcher publishes a verdict without checking coverage.
#
# No real reviewer is spawned and nothing outside the temp dir is written.
# Usage: scripts/check-cold-reviewer-packet.sh   (exit 0 = pass; check-framework.sh runs it)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REVIEWER="$SCRIPT_DIR/run-cold-reviewer.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/cold-reviewer-packet.XXXXXX")" || exit 1
WORK="$(cd "$WORK" && pwd -P)"
trap '[ -n "${KEEP_WORK:-}" ] || rm -rf "$WORK"' EXIT

failures=0
pass() { echo "ok   $*"; }
bad() { echo "FAIL $*" >&2; failures=$((failures + 1)); }

sha() { python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }

# ── stub reviewer CLIs ──────────────────────────────────────────────────────
# Each records the prompt it was given, then answers per STUB_MODE:
#   all          Artifacts-read lists every artifacts.sha256 entry
#   primary-only Artifacts-read lists the primary alone (the #79 failure)
#   missing      no Artifacts-read field
STUBS="$WORK/stubs"
mkdir -p "$STUBS"
cat > "$STUBS/verdict.py" <<'PY'
import json, os, sys
ctx, out = sys.argv[1:3]
entries = [l.rstrip("\n").split("  ", 1) for l in open(os.path.join(ctx, "artifacts.sha256")) if l.strip()]
primary = open(os.path.join(ctx, "artifact.sha256")).read().split()[0]
verdict = {
    "Decision": "proceed",
    "Artifact-hash": primary,
    "Uncertainties": "none (stub)",
    "Rationale": "stub reviewer",
    "Required-changes": "none",
    "Escalation": "none",
    "Ledger": "stub",
}
mode = os.environ.get("STUB_MODE", "all")
if mode == "all":
    verdict["Artifacts-read"] = [{"path": rel, "sha256": d} for d, rel in entries]
elif mode == "primary-only":
    verdict["Artifacts-read"] = [{"path": entries[0][1], "sha256": entries[0][0]}]
elif mode == "extra":
    verdict["Artifacts-read"] = [{"path": rel, "sha256": d} for d, rel in entries]
    verdict["Artifacts-read"].append({"path": "never-staged.md", "sha256": "0" * 64})
json.dump(verdict, open(out, "w"))
PY
cat > "$STUBS/claude" <<'SH'
#!/usr/bin/env bash
for last; do :; done
printf '%s' "$last" > "$STUB_PROMPT_OUT"
python3 "$(dirname "$0")/verdict.py" "$PWD" "$STUB_PROMPT_OUT.verdict" || exit 1
jq -c '{type: "result", structured_output: .}' "$STUB_PROMPT_OUT.verdict"
SH
cat > "$STUBS/codex" <<'SH'
#!/usr/bin/env bash
ctx="" out=""
while [ "$#" -gt 1 ]; do
  case "$1" in
    -C) ctx="$2"; shift 2 ;;
    -o) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
printf '%s' "$1" > "$STUB_PROMPT_OUT"
python3 "$(dirname "$0")/verdict.py" "$ctx" "$out" || exit 1
echo '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}'
SH
chmod +x "$STUBS/claude" "$STUBS/codex"

# ── packet ─────────────────────────────────────────────────────────────────
new_packet() {
  run_dir="$WORK/run-$1"
  ctx="$run_dir/checkpoints/02-context"
  mkdir -p "$ctx/conventions"
  : > "$run_dir/log.md"
  echo '{}' > "$run_dir/state.json"
  cp "$ROOT/AGENTS.md" "$ctx/bureau-agents.md"
  echo "# reviewer slice (stub)" > "$ctx/delegate-reviewer.md"
  echo "# conventions router (stub)" > "$ctx/conventions.md"
  echo "# module (stub)" > "$ctx/conventions/module.md"
  echo "# slice (stub)" > "$ctx/log-slice.md"
  echo '{}' > "$ctx/state.json"
  printf '# Plan\n\nPhase 1 depends on spec.md component 8.\n' > "$ctx/plan.md"
  printf '# Spec\n\nComponent 8: the proxy rollback.\n' > "$ctx/spec.md"
}

run_reviewer() {  # <host> <mode> <spawn-id> -> meta JSON on stdout
  BUREAU_REVIEWER_HOST="$1" STUB_MODE="$2" STUB_PROMPT_OUT="$WORK/prompt-$3" \
  CLAUDE_BIN="$STUBS/claude" CODEX_BIN="$STUBS/codex" \
    bash "$REVIEWER" "$run_dir" "$ctx" 02 "$3" plan.md routine 2> "$WORK/stderr-$3"
}

prompt_names_both() {  # <prompt-file> <root> <label>
  prompt="$(cat "$1")"
  plan_sha="$(sha "$ctx/plan.md")"
  spec_sha="$(sha "$ctx/spec.md")"
  case "$prompt" in
    *"$2/plan.md (the primary artifact, sha256 $plan_sha)"*) pass "$3: prompt names plan.md with its digest" ;;
    *) bad "$3: prompt does not name plan.md as the primary artifact with its digest" ;;
  esac
  case "$prompt" in
    *"$2/spec.md (a supplementary artifact, sha256 $spec_sha)"*) pass "$3: prompt names spec.md with its digest" ;;
    *) bad "$3: prompt does not name the second artifact spec.md with its digest" ;;
  esac
  case "$prompt" in
    *"$2/conventions/module.md"*|*"$2/bureau-agents.md (the primary"*) bad "$3: prompt lists an infrastructure file as an artifact" ;;
    *) pass "$3: infrastructure files are not listed as artifacts" ;;
  esac
}

# 1. Claude host, complete verdict.
new_packet claude-all
meta="$(run_reviewer claude all 02-1)" || { bad "claude/all: reviewer script failed: $(cat "$WORK/stderr-02-1")"; meta='{}'; }
expected_manifest="$(printf '%s  plan.md\n%s  spec.md' "$(sha "$ctx/plan.md")" "$(sha "$ctx/spec.md")")"
if [ "$(cat "$ctx/artifacts.sha256" 2>/dev/null)" = "$expected_manifest" ]; then
  pass "artifacts.sha256 lists plan.md then spec.md with their digests"
else
  bad "artifacts.sha256 is wrong: $(cat "$ctx/artifacts.sha256" 2>/dev/null)"
fi
prompt_names_both "$WORK/prompt-02-1" "$ctx" "claude"
if printf '%s' "$meta" | jq -e '.hash_match == true and .artifacts_read_complete == true and .artifacts_unread == []' >/dev/null 2>&1; then
  pass "claude/all: verdict covering both artifacts is complete"
else
  bad "claude/all: expected artifacts_read_complete true, got $meta"
fi

# 2. Claude host, verdict that skips spec.md.
new_packet claude-primary
meta="$(run_reviewer claude primary-only 02-2)" || { bad "claude/primary-only: reviewer script failed: $(cat "$WORK/stderr-02-2")"; meta='{}'; }
if printf '%s' "$meta" | jq -e '.artifacts_read_complete == false and .artifacts_unread == ["spec.md"]' >/dev/null 2>&1; then
  pass "claude/primary-only: skipping spec.md is reported as incomplete"
else
  bad "claude/primary-only: a verdict that skipped spec.md was not flagged: $meta"
fi
if grep -q "Artifacts-read does not match the packet manifest" "$run_dir/log.md"; then
  pass "claude/primary-only: the gap is logged to log.md"
else
  bad "claude/primary-only: no log.md warning for the unread artifact"
fi

# 3. Claude host, verdict with no Artifacts-read.
new_packet claude-missing
if run_reviewer claude missing 02-3 >/dev/null; then
  bad "claude/missing: a verdict without Artifacts-read was accepted"
else
  pass "claude/missing: a verdict without Artifacts-read is refused"
fi

# 4. Codex host: the prompt names snapshot paths, and coverage still resolves.
new_packet codex-all
meta="$(run_reviewer codex all 02-4)" || { bad "codex/all: reviewer script failed: $(cat "$WORK/stderr-02-4")"; meta='{}'; }
snap_root="$(sed -n 's|.*beginning with \(/[^ ]*/staged\)/bureau-agents.md (the immutable.*|\1|p' "$WORK/prompt-02-4")"
if [ -n "$snap_root" ] && [ "$snap_root" != "$ctx" ]; then
  prompt_names_both "$WORK/prompt-02-4" "$snap_root" "codex"
else
  bad "codex/all: could not find the snapshot root in the prompt"
fi
if printf '%s' "$meta" | jq -e '.artifacts_read_complete == true' >/dev/null 2>&1; then
  pass "codex/all: verdict covering both artifacts is complete"
else
  bad "codex/all: expected artifacts_read_complete true, got $meta"
fi

# 5. Cursor host, phase 1: the Task plan's prompt names both artifacts.
new_packet cursor-plan
BUREAU_REVIEWER_HOST=cursor bash "$REVIEWER" "$run_dir" "$ctx" 02 02-5 plan.md routine \
  > /dev/null 2> "$WORK/stderr-02-5"
rc=$?
plan="$run_dir/checkpoints/02-5-reviewer-task-plan.json"
if [ "$rc" -eq 2 ] && jq -r '.taskPrompt' "$plan" > "$WORK/prompt-02-5" 2>/dev/null; then
  prompt_names_both "$WORK/prompt-02-5" "$ctx" "cursor"
else
  bad "cursor: phase 1 did not produce a Task plan (exit $rc): $(cat "$WORK/stderr-02-5")"
fi

# 6. Cursor resume on the unchanged packet completes.
STUB_MODE=all python3 "$STUBS/verdict.py" "$ctx" "$WORK/response-02-5.json"
meta="$(BUREAU_REVIEWER_HOST=cursor bash "$REVIEWER" --resume "$WORK/response-02-5.json" \
  "$run_dir" "$ctx" 02 02-5 plan.md routine 2> "$WORK/stderr-02-5r")" \
  || { bad "cursor/resume: resume on the unchanged packet failed: $(cat "$WORK/stderr-02-5r")"; meta='{}'; }
if printf '%s' "$meta" | jq -e '.artifacts_read_complete == true' >/dev/null 2>&1; then
  pass "cursor/resume: resume on the unchanged packet is complete"
else
  bad "cursor/resume: expected artifacts_read_complete true, got $meta"
fi

# 7. Cursor resume after spec.md left the packet is refused: the plan is bound to the
#    manifest, so a response that never read spec.md cannot be certified complete.
new_packet cursor-shrunk
BUREAU_REVIEWER_HOST=cursor bash "$REVIEWER" "$run_dir" "$ctx" 02 02-6 plan.md routine \
  > /dev/null 2>&1
rm -f "$ctx/spec.md"
STUB_MODE=primary-only python3 "$STUBS/verdict.py" "$ctx" "$WORK/response-02-6.json"
if BUREAU_REVIEWER_HOST=cursor bash "$REVIEWER" --resume "$WORK/response-02-6.json" \
     "$run_dir" "$ctx" 02 02-6 plan.md routine > /dev/null 2> "$WORK/stderr-02-6r"; then
  bad "cursor/shrunk: resume was accepted after spec.md left the planned packet"
elif grep -q "artifactsManifestSha256 mismatch" "$WORK/stderr-02-6r"; then
  pass "cursor/shrunk: resume is refused when the packet no longer matches the plan"
else
  bad "cursor/shrunk: resume failed for the wrong reason: $(cat "$WORK/stderr-02-6r")"
fi

# 8. A verdict claiming an artifact that was never staged is not complete.
new_packet claude-extra
meta="$(run_reviewer claude extra 02-7)" || { bad "claude/extra: reviewer script failed: $(cat "$WORK/stderr-02-7")"; meta='{}'; }
if printf '%s' "$meta" | jq -e '.artifacts_read_complete == false and .artifacts_unread == [] and (.artifacts_unexpected | length) == 1' >/dev/null 2>&1; then
  pass "claude/extra: an Artifacts-read entry outside the manifest is reported as unexpected"
else
  bad "claude/extra: an entry outside the manifest was not flagged: $meta"
fi

# 9. The v1 watcher must not publish a verdict whose coverage is incomplete.
if grep -Fq ".artifacts_read_complete == true" "$SCRIPT_DIR/watcher.sh"; then
  pass "watcher: publishes a reviewer verdict only when artifacts_read_complete is true"
else
  bad "watcher: does not gate the reviewer verdict on artifacts_read_complete"
fi

if [ "$failures" -gt 0 ]; then
  echo "check-cold-reviewer-packet: $failures failure(s)" >&2
  exit 1
fi
echo "check-cold-reviewer-packet: all checks passed"
