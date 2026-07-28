#!/usr/bin/env bash
# run-start.sh — Bureau run opening ceremony (FR 1, FR 2, FR 3 / Phase 3).
#
# Performs the full opening sequence for a new bureau run:
#   1. Parse + validate arguments
#   2. Resume gate — refuse if RUN_DIR already exists (EC 1)
#   3. Create RUN_DIR
#   4. Ensure .bureau/runs/ and .bureau/archive/ are gitignored in target repo
#   5. Copy templates/state.json, patch target_repo + workflow, validate JSON
#   6. Initialize log.md via log-append.sh
#   7. Write runs-index entry (atomic .tmp → mv; validate)
#   8. Call resolve-model-routing.sh; roll back RUN_DIR on failure (EC 2)
#   9. Pointer enrolment (FR 2): resolve pointer path, write pointer JSON,
#      echo it to stdout by default (nonce credential for direct-Conductor runs;
#      Delegate v2 passes --no-pointer-echo so the bare pointer nonce does not
#      enter the Delegate transcript), append nonce-free enrolment log line
#
# Usage:
#   run-start.sh <RUN_DIR> --target <repo> --workflow <id> --slug <slug>
#                [--runtime <claude|openai>] [--no-pointer-echo]
#
# Arguments:
#   <RUN_DIR>          absolute path where the new run dir will be created
#   --target <repo>    absolute path to the target git repository
#   --workflow <id>    workflow identifier (e.g. "feature", "execute-plan")
#   --slug <slug>      run slug (e.g. "20260712-my-task")
#
# Exit codes:
#   0  run dir created, all artifacts written, pointer enrolled
#   1  argument error, RUN_DIR already exists (EC 1), or a step failed with
#      RUN_DIR rolled back (EC 2)
#
# EC 2 rollback invariant: the rm -rf on failure removes ONLY the RUN_DIR this
# invocation created. The resume gate (step 2) guarantees RUN_DIR did not exist
# before step 3 ran mkdir — so by the time step 8 can fail, this invocation is
# the sole creator. A pre-existing RUN_DIR can never reach step 8.
#
# Bash 3.2 + jq; macOS portable. No set -e (we handle errors explicitly to
# support the EC 2 rollback). No GNU-only date flags.

# Step 0: PATH pin (EC 10 — ugrep guard; also needed for date, jq, python3).
PATH=/usr/bin:$PATH

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Step 1: Parse args ────────────────────────────────────────────────────────

usage() {
  cat >&2 <<'EOF'
Usage:
  run-start.sh <RUN_DIR> --target <repo> --workflow <id> --slug <slug> [--runtime <id>] [--no-pointer-echo]
EOF
  exit 1
}

print_help() {
  cat <<'EOF'
Usage:
  run-start.sh <RUN_DIR> --target <repo> --workflow <id> --slug <slug> [--runtime <id>] [--no-pointer-echo]

Options:
  --runtime <id>     Resolve this run for an explicit host runtime. Supported
                     first-class hosts: claude and openai (codex is an alias
                     for openai). If omitted, model-policy.v2.json decides.
  --no-pointer-echo  Write the normal bare run pointer but do not echo its nonce.
                     Use only when a Delegate v2 top session is creating the run;
                     the Conductor subagent will read the pointer privately before
                     spawning specialists, and the Delegate will enroll/echo its
                     own role:delegate pointer.
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  print_help
  exit 0
fi

if [ "$#" -lt 1 ]; then
  echo "run-start: missing required argument: <RUN_DIR>" >&2
  usage
fi

RUN_DIR="$1"; shift

TARGET=""
WORKFLOW=""
SLUG=""
POINTER_ECHO=1
MODEL_RUNTIME=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target)
      [ "$#" -ge 2 ] || { echo "run-start: missing argument: --target" >&2; exit 1; }
      TARGET="$2"; shift 2 ;;
    --workflow)
      [ "$#" -ge 2 ] || { echo "run-start: missing argument: --workflow" >&2; exit 1; }
      WORKFLOW="$2"; shift 2 ;;
    --slug)
      [ "$#" -ge 2 ] || { echo "run-start: missing argument: --slug" >&2; exit 1; }
      SLUG="$2"; shift 2 ;;
    --runtime)
      [ "$#" -ge 2 ] || { echo "run-start: missing argument: --runtime" >&2; exit 1; }
      MODEL_RUNTIME="$2"; shift 2 ;;
    --no-pointer-echo)
      POINTER_ECHO=0; shift ;;
    --help|-h)
      print_help
      exit 0 ;;
    *)
      echo "run-start: unknown argument: $1" >&2; usage ;;
  esac
done

if [ -z "$TARGET" ]; then
  echo "run-start: missing argument: --target" >&2; exit 1
fi
if [ -z "$WORKFLOW" ]; then
  echo "run-start: missing argument: --workflow" >&2; exit 1
fi
if [ -z "$SLUG" ]; then
  echo "run-start: missing argument: --slug" >&2; exit 1
fi
if [ "$MODEL_RUNTIME" = "codex" ]; then
  MODEL_RUNTIME="openai"
fi
case "$MODEL_RUNTIME" in
  ""|claude|openai) ;;
  *) echo "run-start: unsupported first-class runtime: $MODEL_RUNTIME" >&2; exit 1 ;;
esac

# ── Step 2: Resume gate (EC 1) ────────────────────────────────────────────────
# If RUN_DIR already exists, refuse — caller must use the resume protocol.

if [ -e "$RUN_DIR" ]; then
  echo "ERROR: RUN_DIR already exists — use resume protocol, not run-start." >&2
  exit 1
fi

# ── Step 3: Create RUN_DIR ────────────────────────────────────────────────────

mkdir -p "$RUN_DIR" || { echo "run-start: failed to create RUN_DIR: $RUN_DIR" >&2; exit 1; }

# All subsequent failures trigger the EC 2 rollback.
# EC 2 invariant: removes ONLY the RUN_DIR this invocation created, plus any
# runs-index entry (committed or .tmp) written during this ceremony so a failed
# run-start leaves NO trace in the index.
rollback() {
  echo "run-start: rolling back RUN_DIR: $RUN_DIR" >&2
  rm -rf "$RUN_DIR"
  # Remove any runs-index artifacts written by this invocation (EC 2).
  # RUNS_INDEX and SLUG may not be set yet if failure occurs before step 7,
  # so guard each removal — the variables resolve at call time.
  if [ -n "${RUNS_INDEX:-}" ] && [ -n "${SLUG:-}" ]; then
    rm -f "$RUNS_INDEX/.$SLUG.json.tmp" "$RUNS_INDEX/$SLUG.json"
  fi
  exit 1
}

# ── Step 4: ensure-bureau-ignored.sh <target> ─────────────────────────────────

if ! bash "$FRAMEWORK_ROOT/scripts/ensure-bureau-ignored.sh" "$TARGET" >&2; then
  echo "ERROR: ensure-bureau-ignored.sh failed for target: $TARGET" >&2
  rollback
fi

# ── Step 5: Copy + patch state.json, validate ─────────────────────────────────

STATE_TEMPLATE="$FRAMEWORK_ROOT/templates/state.json"
STATE_PATH="$RUN_DIR/state.json"

if [ ! -f "$STATE_TEMPLATE" ]; then
  echo "ERROR: templates/state.json not found at $STATE_TEMPLATE" >&2
  rollback
fi

cp "$STATE_TEMPLATE" "$STATE_PATH" || rollback

jq --arg tr "$TARGET" --arg wf "$WORKFLOW" \
   '.target_repo = $tr | .workflow = $wf' \
   "$STATE_PATH" > "$STATE_PATH.tmp" \
  && mv "$STATE_PATH.tmp" "$STATE_PATH" \
  || { echo "ERROR: failed to patch state.json" >&2; rollback; }

python3 -c "import json,sys; json.load(open('$STATE_PATH'))" \
  || { echo "ERROR: state.json invalid after template copy" >&2; rollback; }

# ── Step 6: Initialize log.md via log-append.sh ───────────────────────────────

bash "$FRAMEWORK_ROOT/scripts/log-append.sh" "$RUN_DIR" \
    "Run started — slug: $SLUG, target: $TARGET, workflow: $WORKFLOW" >/dev/null \
  || { echo "ERROR: log-append.sh failed" >&2; rollback; }

# ── Step 7: Write runs-index entry (atomic) ───────────────────────────────────

RUNS_INDEX="$FRAMEWORK_ROOT/output/studio/runs-index"
mkdir -p "$RUNS_INDEX" "$RUNS_INDEX/archive" \
  || { echo "ERROR: failed to create runs-index dir" >&2; rollback; }

INDEX_ENTRY="$RUNS_INDEX/$SLUG.json"
# Seven-field projection per docs/run-protocol.md § Index write:
#   slug, repo (target_repo), run_dir, status (derived), phase, last_updated, workflow
# Status derivation: template default (phase_status=pending, phases_complete=[]) → "not_started"
jq -n \
  --arg slug        "$SLUG" \
  --arg repo        "$(jq -r '.target_repo // ""' "$STATE_PATH")" \
  --arg run_dir     "$RUN_DIR" \
  --arg phase       "$(jq -r '.phase // "not_started"' "$STATE_PATH")" \
  --argjson last_updated "$(jq '.last_updated' "$STATE_PATH")" \
  --arg workflow    "$(jq -r '.workflow // ""' "$STATE_PATH")" \
  '{slug: $slug,
    repo: $repo,
    run_dir: $run_dir,
    status: "not_started",
    phase: $phase,
    last_updated: $last_updated,
    workflow: $workflow}' \
  > "$RUNS_INDEX/.$SLUG.json.tmp" \
  || { echo "ERROR: failed to build runs-index entry" >&2; rollback; }

mv "$RUNS_INDEX/.$SLUG.json.tmp" "$INDEX_ENTRY" \
  || { echo "ERROR: failed to write runs-index entry" >&2; rollback; }

python3 -c "import json,sys; json.load(open('$INDEX_ENTRY'))" \
  || { echo "ERROR: runs-index entry invalid" >&2; rollback; }

# ── Step 8: resolve-model-routing.sh (EC 2 rollback on failure) ──────────────

if [ -n "$MODEL_RUNTIME" ]; then
  NOVADIEM_MODEL_RUNTIME="$MODEL_RUNTIME" \
    bash "$FRAMEWORK_ROOT/scripts/resolve-model-routing.sh" "$RUN_DIR/model-routing.json" >&2
else
  bash "$FRAMEWORK_ROOT/scripts/resolve-model-routing.sh" "$RUN_DIR/model-routing.json" >&2
fi
if [ $? -ne 0 ] || [ ! -s "$RUN_DIR/model-routing.json" ]; then
  echo "ERROR: resolve-model-routing.sh failed or produced empty output — rolling back RUN_DIR" >&2
  rollback
fi

_resolved_runtime="$(jq -r '.runtime // "unknown"' "$RUN_DIR/model-routing.json" 2>/dev/null)"
bash "$FRAMEWORK_ROOT/scripts/log-append.sh" "$RUN_DIR" \
  "Host runtime resolved — runtime: $_resolved_runtime" >/dev/null \
  || { echo "ERROR: log-append.sh failed for runtime line" >&2; rollback; }

# ── Step 9: Pointer enrolment (FR 2 nonce-echo) ───────────────────────────────
#
# Path-resolution block — IDENTICAL to orchestrator.md § Pointer lifecycle
# (lines 455-468) and byte-compatible with conductor-stop.sh (lines 63-76).
# Precedence:
#   1. BUREAU_POINTER_FILE set (non-empty) → FORCED single-file mode at that path.
#   2. Else → directory mode keyed by munged RUN_DIR under BUREAU_POINTER_DIR.
#
# The key is the munged RUN_DIR (not the nonce): a resumed leg of the same run has
# the same RUN_DIR → same file. Two distinct runs have distinct RUN_DIRs → distinct
# files (no clobber). Tests set BUREAU_POINTER_DIR to a mktemp dir — never touching
# the real ~/.novadiem/active-runs/.

if [ -n "${BUREAU_POINTER_FILE:-}" ]; then
  _pointer_file="$BUREAU_POINTER_FILE"
else
  _pointer_dir="${BUREAU_POINTER_DIR:-$HOME/.novadiem/active-runs}"
  _ptr_key=$(printf '%s' "$RUN_DIR" | sed 's#[/.]#-#g')   # munge / and . → -
  _pointer_file="$_pointer_dir/$_ptr_key"
fi

mkdir -p "$(dirname "$_pointer_file")" \
  || { echo "ERROR: failed to create pointer dir: $(dirname "$_pointer_file")" >&2; rollback; }

printf '{"run_dir":"%s","nonce":"%s","written_at":"%s","baseline":null,"project_dir":"%s"}\n' \
  "$RUN_DIR" \
  "$(uuidgen | tr '[:upper:]' '[:lower:]')" \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "$(pwd -P)" \
  > "$_pointer_file" \
  || { echo "ERROR: failed to write pointer file" >&2; rollback; }

# FR 2: nonce-echo to stdout for direct-Conductor runs — NEVER stderr-only.
# Delegate v2 is the exception: the top session is the Delegate, so echoing the
# bare Conductor/specialist pointer would put that nonce in the Delegate
# transcript and let conductor-stop.sh misselect the bare pointer before the
# role:delegate pointer. In that topology, the pointer is still written; the
# Conductor subagent reads it privately before spawning specialists.
if [ "$POINTER_ECHO" -eq 1 ]; then
  # The nonce NEVER appears in log.md or any artifact other than the pointer file
  # and the owning transcript.
  cat "$_pointer_file"
else
  echo "run-start: pointer enrolled; bare pointer nonce echo suppressed for Delegate v2 startup" >&2
fi

# Enrolment log line — nonce-free (reading the log must not confer ownership).
if [ "$POINTER_ECHO" -eq 1 ]; then
  _enrolment_msg="Pointer enrolled — nonce written to pointer file and conductor transcript only. Reading this log does not confer ownership."
else
  _enrolment_msg="Pointer enrolled — nonce written to pointer file only; Delegate v2 suppressed bare nonce echo. Reading this log does not confer ownership."
fi

bash "$FRAMEWORK_ROOT/scripts/log-append.sh" "$RUN_DIR" \
  "$_enrolment_msg" >/dev/null \
  || { echo "ERROR: log-append.sh failed for enrolment line" >&2; rollback; }

exit 0
