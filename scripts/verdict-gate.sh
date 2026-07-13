#!/usr/bin/env bash
# Bash 3.2 / macOS: no associative arrays, no Bash-4+ bulk-read array builtins, no advisory file locking, no set -e.
PATH=/usr/bin:$PATH                         # EC-10 / AC-16: ugrep guard

# verdict-gate.sh — Revalidate a Challenger verdict record after the review.
#
# Usage:
#   verdict-gate.sh <RUN_DIR> <attempt_id>
#
# Exit codes:
#   exit 0  + stdout "gate: clean"                   — all checks pass
#   exit 1  + one DEFECT line per failing class       — one or more failures
#   exit 2  + stderr message                          — bad args or unreadable RUN_DIR

# ── Argument validation (exit 2) ──────────────────────────────────────────────

RUN_DIR="$1"
ATTEMPT_ID="$2"

if [ -z "$RUN_DIR" ]; then
  echo "Usage: verdict-gate.sh <RUN_DIR> <attempt_id>" >&2
  exit 2
fi

if [ ! -d "$RUN_DIR" ] || [ ! -r "$RUN_DIR" ]; then
  echo "verdict-gate: RUN_DIR not a readable directory: $RUN_DIR" >&2
  exit 2
fi

if [ -z "$ATTEMPT_ID" ]; then
  echo "verdict-gate: attempt_id argument missing" >&2
  exit 2
fi

# ── STEP 1 — Record present ───────────────────────────────────────────────────

RECORD="$RUN_DIR/verdicts/$ATTEMPT_ID.json"

if [ ! -f "$RECORD" ]; then
  echo "DEFECT: absent record — $RECORD not found"
  exit 1
fi

# ── STEP 2 — Schema + enum + derived-consistency (python3, no jsonschema) ─────
# NOTE: Do NOT use # x) style comments inside this heredoc. Bash 3.2 counts
# ')' inside $(...) heredocs even in quoted delimiters, so '#a)' breaks parsing.

STEP2_OUT="$(python3 - "$RECORD" <<'PY'
import json, sys

path = sys.argv[1]
try:
    with open(path) as fh:
        data = json.load(fh)
except Exception as e:
    print("DEFECT: schema-violation — bad JSON: %s" % e)
    sys.exit(1)

if not isinstance(data, dict):
    print("DEFECT: schema-violation — record is not a JSON object")
    sys.exit(1)

# Check: all 8 required fields present and non-None
required = ["attempt_id", "review_mode", "reviewed_artifacts",
            "blocker_ids", "blockers", "warnings", "verdict", "timestamp"]
for f in required:
    if f not in data or data[f] is None:
        print("DEFECT: schema-violation — missing required field: %s" % f)
        sys.exit(1)

# Check: review_mode enum
valid_modes = {"spec-plan", "prompts", "build-diff", "code-review", "verification"}
if data["review_mode"] not in valid_modes:
    print("DEFECT: schema-violation — invalid review_mode: %s" % data["review_mode"])
    sys.exit(1)

# Check: verdict enum
valid_verdicts = {"APPROVED", "BLOCKED", "APPROVED_WITH_WARNINGS"}
if data["verdict"] not in valid_verdicts:
    print("DEFECT: schema-violation — invalid verdict: %s" % data["verdict"])
    sys.exit(1)

# Check: derived-verdict consistency
blocker_ids = data["blocker_ids"]
warnings = data["warnings"]
verdict = data["verdict"]
if not isinstance(blocker_ids, list):
    print("DEFECT: schema-violation — blocker_ids must be an array")
    sys.exit(1)
if not isinstance(warnings, list):
    print("DEFECT: schema-violation — warnings must be an array")
    sys.exit(1)
if len(blocker_ids) > 0 and verdict != "BLOCKED":
    print("DEFECT: schema-violation — blocker_ids non-empty but verdict is %s (must be BLOCKED)" % verdict)
    sys.exit(1)
if len(blocker_ids) == 0 and len(warnings) > 0 and verdict != "APPROVED_WITH_WARNINGS":
    print("DEFECT: schema-violation — blocker_ids empty, warnings non-empty, but verdict is %s (must be APPROVED_WITH_WARNINGS)" % verdict)
    sys.exit(1)
if len(blocker_ids) == 0 and len(warnings) == 0 and verdict != "APPROVED":
    print("DEFECT: schema-violation — blocker_ids and warnings both empty but verdict is %s (must be APPROVED)" % verdict)
    sys.exit(1)

# Check: reviewed_artifacts shape
if not isinstance(data["reviewed_artifacts"], list):
    print("DEFECT: schema-violation — reviewed_artifacts must be an array")
    sys.exit(1)
for i, art in enumerate(data["reviewed_artifacts"]):
    if not isinstance(art, dict):
        print("DEFECT: schema-violation — reviewed_artifacts[%d] is not an object" % i)
        sys.exit(1)
    if "kind" not in art:
        # file-target shape: must have path and sha256
        if "path" not in art or "sha256" not in art:
            print("DEFECT: schema-violation — reviewed_artifacts[%d] file-target missing path or sha256" % i)
            sys.exit(1)
    else:
        # diff-target shape
        if art.get("kind") != "diff-target":
            print("DEFECT: schema-violation — reviewed_artifacts[%d] unknown kind: %s" % (i, art.get("kind")))
            sys.exit(1)
        for k in ["kind", "base_ref", "base_sha", "target_ref", "diff_sha"]:
            if k not in art or art[k] is None:
                print("DEFECT: schema-violation — reviewed_artifacts[%d] diff-target missing field: %s" % (i, k))
                sys.exit(1)

# Check: blockers shape
if not isinstance(data["blockers"], list):
    print("DEFECT: schema-violation — blockers must be an array")
    sys.exit(1)
for i, blk in enumerate(data["blockers"]):
    if not isinstance(blk, dict):
        print("DEFECT: schema-violation — blockers[%d] is not an object" % i)
        sys.exit(1)
    for k in ["id", "summary", "citation"]:
        if k not in blk or blk[k] is None:
            print("DEFECT: schema-violation — blockers[%d] missing field: %s" % (i, k))
            sys.exit(1)
    cit = blk["citation"]
    if not isinstance(cit, dict):
        print("DEFECT: schema-violation — blockers[%d] citation is not an object" % i)
        sys.exit(1)
    cit_kind = cit.get("kind")
    if cit_kind not in ("presence", "absence"):
        print("DEFECT: schema-violation — blockers[%d] citation.kind must be 'presence' or 'absence', got: %s" % (i, cit_kind))
        sys.exit(1)
    if cit_kind == "presence":
        anchor = cit.get("anchor")
        if not anchor:
            print("DEFECT: schema-violation — blockers[%d] presence citation missing or empty anchor field" % i)
            sys.exit(1)
    if cit_kind == "absence":
        missing = cit.get("missing")
        if not missing:
            print("DEFECT: schema-violation — blockers[%d] absence citation missing or empty missing field" % i)
            sys.exit(1)

sys.exit(0)
PY
)"

STEP2_STATUS=$?
if [ "$STEP2_STATUS" -ne 0 ]; then
  echo "$STEP2_OUT"
  exit 1
fi

# ── STEP 3 — Reviewed-change revalidation ────────────────────────────────────

# Extract review_mode and artifact data using python3
STEP3_INFO="$(python3 - "$RECORD" <<'PY'
import json, sys

path = sys.argv[1]
with open(path) as fh:
    data = json.load(fh)

mode = data["review_mode"]
print("REVIEW_MODE=" + mode)

file_modes = {"spec-plan", "prompts", "verification"}
diff_modes = {"build-diff", "code-review"}

if mode in file_modes:
    for i, art in enumerate(data["reviewed_artifacts"]):
        print("FILE_PATH_" + str(i) + "=" + art["path"])
        print("FILE_SHA_" + str(i) + "=" + art["sha256"])
    print("FILE_COUNT=" + str(len(data["reviewed_artifacts"])))
elif mode in diff_modes:
    art = data["reviewed_artifacts"][0]
    print("DIFF_BASE_REF=" + art["base_ref"])
    print("DIFF_BASE_SHA=" + art["base_sha"])
    print("DIFF_TARGET_REF=" + art["target_ref"])
    print("DIFF_SHA=" + art["diff_sha"])
PY
)"

STEP3_STATUS=$?
if [ "$STEP3_STATUS" -ne 0 ]; then
  echo "DEFECT: schema-violation — could not extract artifact data from record"
  exit 1
fi

# Parse the emitted key=value lines into shell variables
REVIEW_MODE=""
FILE_COUNT=0
DIFF_BASE_REF=""
DIFF_BASE_SHA=""
DIFF_TARGET_REF=""
DIFF_SHA=""

while IFS= read -r _line; do
  case "$_line" in
    REVIEW_MODE=*)    REVIEW_MODE="${_line#REVIEW_MODE=}" ;;
    FILE_COUNT=*)     FILE_COUNT="${_line#FILE_COUNT=}" ;;
    DIFF_BASE_REF=*)  DIFF_BASE_REF="${_line#DIFF_BASE_REF=}" ;;
    DIFF_BASE_SHA=*)  DIFF_BASE_SHA="${_line#DIFF_BASE_SHA=}" ;;
    DIFF_TARGET_REF=*) DIFF_TARGET_REF="${_line#DIFF_TARGET_REF=}" ;;
    DIFF_SHA=*)       DIFF_SHA="${_line#DIFF_SHA=}" ;;
  esac
done <<EOF
$STEP3_INFO
EOF

# File-target modes: recheck hashes
case "$REVIEW_MODE" in
  spec-plan|prompts|verification)
    _i=0
    while [ "$_i" -lt "$FILE_COUNT" ]; do
      # Read path and sha for index _i from STEP3_INFO
      _path=""
      _sha=""
      while IFS= read -r _line; do
        case "$_line" in
          "FILE_PATH_${_i}="*) _path="${_line#FILE_PATH_${_i}=}" ;;
          "FILE_SHA_${_i}="*)  _sha="${_line#FILE_SHA_${_i}=}" ;;
        esac
      done <<EOF
$STEP3_INFO
EOF

      if [ ! -f "$_path" ]; then
        echo "DEFECT: hash-mismatch for $_path — file not on disk"
        exit 1
      fi

      # PINNED INVOCATION: shasum -a 256 "$path" | awk '{print $1}'
      if command -v shasum >/dev/null 2>&1; then
        _computed=$(shasum -a 256 "$_path" | awk '{print $1}')
      else
        _computed=$(sha256sum "$_path" | awk '{print $1}')
      fi

      if [ "$_computed" != "$_sha" ]; then
        echo "DEFECT: hash-mismatch for $_path — expected $_sha got $_computed"
        exit 1
      fi

      _i=$((_i + 1))
    done
    ;;

  build-diff|code-review)
    # Read target_repo from state.json
    _state="$RUN_DIR/state.json"
    if [ ! -f "$_state" ]; then
      echo "DEFECT: diff-target-mutated — diff-target record on (no-target) run (no git repo)"
      exit 1
    fi

    _target_repo="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('target_repo',''))" "$_state" 2>/dev/null)"
    if [ -z "$_target_repo" ] || [ "$_target_repo" = "(no-target)" ]; then
      echo "DEFECT: diff-target-mutated — diff-target record on (no-target) run (no git repo)"
      exit 1
    fi

    R="$_target_repo"

    # Re-derive base_sha from base_ref
    if [ "$DIFF_TARGET_REF" = "WORKING-TREE" ]; then
      _recomputed_base=$(git -C "$R" rev-parse HEAD 2>/dev/null)
    else
      case "$DIFF_BASE_REF" in
        *..*)
          # committed range A..B: base is left side
          _left=$(echo "$DIFF_BASE_REF" | cut -d. -f1)
          _recomputed_base=$(git -C "$R" rev-parse "$_left" 2>/dev/null)
          ;;
        *)
          # branch head: base is merge-base of HEAD and branch
          _recomputed_base=$(git -C "$R" merge-base HEAD "$DIFF_BASE_REF" 2>/dev/null)
          ;;
      esac
    fi

    if [ "$_recomputed_base" != "$DIFF_BASE_SHA" ]; then
      echo "DEFECT: diff-target-mutated — base_sha changed (expected $DIFF_BASE_SHA got $_recomputed_base)"
      exit 1
    fi

    # Recompute diff_sha — PINNED INVOCATION (byte-identical to Challenger write)
    if [ "$DIFF_TARGET_REF" = "WORKING-TREE" ]; then
      # diff-target WORKING-TREE: git -C "$R" diff "$base_sha" | shasum -a 256 | awk '{print $1}'
      _recomputed_diff=$(git -C "$R" diff "$_recomputed_base" | shasum -a 256 | awk '{print $1}')
    else
      _target_sha=$(git -C "$R" rev-parse "$DIFF_TARGET_REF" 2>/dev/null)
      # diff-target committed: git -C "$R" diff "$base_sha" "$target_sha" | shasum -a 256 | awk '{print $1}'
      _recomputed_diff=$(git -C "$R" diff "$_recomputed_base" "$_target_sha" | shasum -a 256 | awk '{print $1}')
    fi

    if [ "$_recomputed_diff" != "$DIFF_SHA" ]; then
      echo "DEFECT: diff-target-mutated — diff_sha changed (expected $DIFF_SHA got $_recomputed_diff)"
      exit 1
    fi
    ;;
esac

# ── STEP 4 — Citation check ───────────────────────────────────────────────────

# Extract blocker citations via python3
BLOCKER_DATA="$(python3 - "$RECORD" <<'PY'
import json, sys

path = sys.argv[1]
with open(path) as fh:
    data = json.load(fh)

for blk in data["blockers"]:
    bid = blk["id"]
    cit = blk["citation"]
    kind = cit["kind"]
    cit_path = cit.get("path", "")
    if kind == "presence":
        anchor = cit.get("anchor", "")
        print("BLOCKER_KIND=presence")
        print("BLOCKER_ID=" + bid)
        print("BLOCKER_PATH=" + cit_path)
        print("BLOCKER_ANCHOR=" + anchor)
        print("BLOCKER_END")
    elif kind == "absence":
        print("BLOCKER_KIND=absence")
        print("BLOCKER_ID=" + bid)
        print("BLOCKER_PATH=" + cit_path)
        print("BLOCKER_END")
PY
)"

# Process each blocker
_bkind=""
_bid=""
_bpath=""
_banchor=""

while IFS= read -r _line; do
  case "$_line" in
    BLOCKER_KIND=*)   _bkind="${_line#BLOCKER_KIND=}" ;;
    BLOCKER_ID=*)     _bid="${_line#BLOCKER_ID=}" ;;
    BLOCKER_PATH=*)   _bpath="${_line#BLOCKER_PATH=}" ;;
    BLOCKER_ANCHOR=*) _banchor="${_line#BLOCKER_ANCHOR=}" ;;
    BLOCKER_END)
      # Process this blocker
      if [ "$_bkind" = "presence" ]; then
        if ! grep -qF "$_banchor" "$_bpath" 2>/dev/null; then
          echo "DEFECT: citation-not-found for blocker $_bid — anchor \"$_banchor\" not found in $_bpath"
          exit 1
        fi
      elif [ "$_bkind" = "absence" ]; then
        if [ ! -f "$_bpath" ]; then
          echo "DEFECT: citation-path-not-found for blocker $_bid — $_bpath not on disk"
          exit 1
        fi
      fi
      # Reset for next blocker
      _bkind=""
      _bid=""
      _bpath=""
      _banchor=""
      ;;
  esac
done <<EOF
$BLOCKER_DATA
EOF

# ── STEP 5 — Clean exit ───────────────────────────────────────────────────────

echo "gate: clean"
exit 0
