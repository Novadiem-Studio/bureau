#!/usr/bin/env bash
# run-cold-reviewer.sh — provider-neutral cold-reviewer dispatcher.
#
# Usage:
#   run-cold-reviewer.sh <RUN_DIR> <CTX> <checkpoint> <spawn-id> <artifact-basename> <routine|integration|readiness-audit>
#
# The caller stages CTX. This script selects the host from model-routing.json
# (`claude` or `openai`/`codex`), runs one fresh reviewer, and writes:
#   checkpoints/<spawn-id>-reviewer-verdict.json
#   checkpoints/<spawn-id>-reviewer-envelope.json
#   checkpoints/<spawn-id>-reviewer-events.jsonl
#   checkpoints/<spawn-id>-reviewer-stderr.log
#
# stdout is one metadata JSON object naming those files. Diagnostics go to
# stderr. The script never appends token events; callers do that exactly once
# after a real spawn by passing reviewer-envelope.json to
# append-reviewer-tokens.sh.

set -u

if [ "$#" -ne 6 ]; then
  echo "run-cold-reviewer: usage: <RUN_DIR> <CTX> <checkpoint> <spawn-id> <artifact-basename> <routine|integration|readiness-audit>" >&2
  exit 1
fi

RUN_DIR="$1"
CTX="$2"
CHECKPOINT="$3"
SPAWN_ID="$4"
ARTIFACT_BASE="$5"
REVIEW_MODE="$6"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROUTING="$RUN_DIR/model-routing.json"

fail() {
  echo "run-cold-reviewer: $*" >&2
  exit 1
}

run_readiness_audit() {
  readiness_schema="$ROOT/config/challenger-verdict.schema.json"
  [ -d "$RUN_DIR" ] || fail "RUN_DIR is not a directory: $RUN_DIR"
  [ -d "$CTX" ] || fail "CTX is not a directory: $CTX"
  [ -f "$readiness_schema" ] || fail "Challenger verdict schema not found: $readiness_schema"
  command -v python3 >/dev/null 2>&1 || fail "python3 is required for readiness packet validation"
  command -v jq >/dev/null 2>&1 || fail "jq is required for readiness reviewer routing"

  readiness_tmp="$(mktemp -d "${TMPDIR:-/tmp}/bureau-readiness-review.XXXXXX")" \
    || fail "cannot create readiness adapter workspace"
  cleanup_readiness_tmp() {
    rm -rf "$readiness_tmp"
  }
  trap cleanup_readiness_tmp EXIT
  packet_state_before="$readiness_tmp/packet-before.json"
  packet_state_after="$readiness_tmp/packet-after.json"

  validate_readiness_packet() {
    state_out="$1"
    validation_phase="$2"
    python3 - "$RUN_DIR" "$CTX" "$ROOT" "$state_out" "$validation_phase" <<'PY'
import datetime
import hashlib
import json
import os
import re
import stat
import sys
import unicodedata

run_dir, packet_root, framework_root, state_out, validation_phase = sys.argv[1:]
if validation_phase not in {"before", "after"}:
    raise SystemExit("run-cold-reviewer: internal readiness validation phase is invalid")

def reject(message):
    raise SystemExit("run-cold-reviewer: readiness packet " + message)

def pairs_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            reject("contains duplicate JSON key: " + key)
        result[key] = value
    return result

def load_json_bytes(path):
    try:
        raw = open(path, "rb").read()
    except OSError as exc:
        reject("cannot read %s: %s" % (path, exc))
    if raw.startswith(b"\xef\xbb\xbf"):
        reject("JSON has a byte order mark: " + path)
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        reject("JSON is not UTF-8: " + path)
    decoder = json.JSONDecoder(
        object_pairs_hook=pairs_object,
        parse_constant=lambda value: reject("JSON contains non-RFC-8259 constant: " + value),
    )
    try:
        value, end = decoder.raw_decode(text)
    except (ValueError, json.JSONDecodeError) as exc:
        reject("invalid JSON in %s: %s" % (path, exc))
    if text[end:].strip():
        reject("JSON has trailing content: " + path)
    return value, raw

def exact_keys(value, keys, label):
    if not isinstance(value, dict) or set(value) != set(keys):
        reject("%s has the wrong exact key set" % label)

SAFE_ID = re.compile(rb"[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?")
PATH_SEGMENT = re.compile(rb"[A-Za-z0-9](?:[A-Za-z0-9._-]{0,62}[A-Za-z0-9_-])?")
SHA256 = re.compile(r"[0-9a-f]{64}")
AUDIT_VERSION = re.compile(r"v(?:000[1-9]|00[1-9][0-9]|0[1-9][0-9]{2}|[1-9][0-9]{3})")
TIMESTAMP = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z")

def safe_id(value, label):
    if not isinstance(value, str):
        reject(label + " is not a string")
    try:
        raw = value.encode("ascii")
    except UnicodeEncodeError:
        reject(label + " is not ASCII")
    if SAFE_ID.fullmatch(raw) is None:
        reject(label + " is malformed")

def safe_packet_path(value, label):
    if not isinstance(value, str):
        reject(label + " is not a string")
    try:
        raw = value.encode("ascii")
    except UnicodeEncodeError:
        reject(label + " is not ASCII")
    if not 1 <= len(raw) <= 512 or raw.startswith(b"/") or b"\\" in raw:
        reject(label + " is unsafe")
    parts = raw.split(b"/")
    if any(PATH_SEGMENT.fullmatch(part) is None for part in parts):
        reject(label + " has an unsafe path segment")
    return raw

def bounded_text(value, limit, label):
    if not isinstance(value, str):
        reject(label + " is not a string")
    size = len(value.encode("utf-8"))
    if not 1 <= size <= limit or any(unicodedata.category(ch) == "Cc" for ch in value):
        reject(label + " is empty, over limit, or contains a control character")

def valid_timestamp(value, label):
    if not isinstance(value, str) or TIMESTAMP.fullmatch(value) is None:
        reject(label + " is not a UTC second-precision timestamp")
    try:
        datetime.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        reject(label + " is not a real timestamp")

def sha_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

def ensure_plain_path(root, relative):
    current = root
    for segment in relative.split("/"):
        current = os.path.join(current, segment)
        try:
            mode = os.lstat(current).st_mode
        except OSError as exc:
            reject("missing payload %s: %s" % (relative, exc))
        if stat.S_ISLNK(mode):
            reject("contains a symlink: " + relative)
    try:
        common = os.path.commonpath([os.path.realpath(current), os.path.realpath(root)])
    except ValueError:
        reject("path escapes packet root: " + relative)
    if common != os.path.realpath(root) or not stat.S_ISREG(os.lstat(current).st_mode):
        reject("payload is not a regular file beneath the packet root: " + relative)
    return current

run_dir = os.path.abspath(run_dir)
packet_root_raw = packet_root
if not os.path.isabs(packet_root_raw) or os.path.normpath(packet_root_raw) != packet_root_raw:
    reject("root must be an absolute, non-normalized path")
packet_root = packet_root_raw
if stat.S_ISLNK(os.lstat(packet_root).st_mode):
    reject("root is a symlink")

packet_path = ensure_plain_path(packet_root, "packet.json")
manifest, manifest_raw = load_json_bytes(packet_path)
manifest_keys = ["schema_version", "audit_version", "corrected_audit_path", "review_question",
                 "attempt_id", "output_id", "review_mode", "denied_inputs", "allowlist"]
exact_keys(manifest, manifest_keys, "packet.json")
if type(manifest["schema_version"]) is not int or manifest["schema_version"] != 1:
    reject("schema_version must be integer 1")
if not isinstance(manifest["audit_version"], str) or AUDIT_VERSION.fullmatch(manifest["audit_version"]) is None:
    reject("audit_version is malformed")
safe_id(manifest["attempt_id"], "attempt_id")
safe_id(manifest["output_id"], "output_id")
bounded_text(manifest["review_question"], 2000, "review_question")
if manifest["review_mode"] != "verification":
    reject("review_mode must be verification")
expected_denied = [
    "run-log",
    "run-state-and-delegate-state",
    "checkpoint-log-slices",
    "prior-challenger-or-notary-findings-and-verdicts",
    "conductor-or-author-rationale",
    "visionary-back-and-forth",
    "chat-and-session-transcripts",
    "files-absent-from-allowlist",
]
if manifest["denied_inputs"] != expected_denied:
    reject("denied_inputs does not match the fixed ordered list")
if not isinstance(manifest["allowlist"], list) or not manifest["allowlist"]:
    reject("allowlist must be a nonempty array")

entries = []
raw_paths = []
seen_lower = set()
for index, item in enumerate(manifest["allowlist"]):
    exact_keys(item, ["path", "sha256"], "allowlist[%d]" % index)
    raw_path = safe_packet_path(item["path"], "allowlist[%d].path" % index)
    if not isinstance(item["sha256"], str) or SHA256.fullmatch(item["sha256"]) is None:
        reject("allowlist[%d].sha256 is missing, uppercase, or malformed" % index)
    lower = raw_path.lower()
    if raw_path in raw_paths:
        reject("allowlist contains a duplicate path")
    if lower in seen_lower:
        reject("allowlist contains a case-colliding path")
    raw_paths.append(raw_path)
    seen_lower.add(lower)
    entries.append((item["path"], item["sha256"]))
if raw_paths != sorted(raw_paths):
    reject("allowlist is not canonically sorted")

forbidden_basenames = {"log.md", "state.json", "delegate-state.json", "log-slice.md"}
for path, unused_hash in entries:
    basename = path.rsplit("/", 1)[-1].lower()
    if (basename in forbidden_basenames or "transcript" in basename or
            "verdict" in basename or basename.startswith("checkpoint-")):
        reject("allowlist contains forbidden run-history basename: " + basename)

audit_version = manifest["audit_version"]
expected_corrected = "audit/versions/%s/corrected-audit.md" % audit_version
if manifest["corrected_audit_path"] != expected_corrected:
    reject("corrected_audit_path does not match audit_version")
safe_packet_path(manifest["corrected_audit_path"], "corrected_audit_path")

# Enumerate without following links. The only regular files must be packet.json
# and the exact allowlist; aliases and special objects fail closed.
actual = []
identities = {}
for current, directories, files in os.walk(packet_root, topdown=True, followlinks=False):
    for name in list(directories):
        full = os.path.join(current, name)
        mode = os.lstat(full).st_mode
        if stat.S_ISLNK(mode) or not stat.S_ISDIR(mode):
            reject("contains a symlink or special directory entry")
    for name in files:
        full = os.path.join(current, name)
        info = os.lstat(full)
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
            reject("contains a symlink or special file")
        relative = os.path.relpath(full, packet_root)
        safe_packet_path(relative, "staged file path")
        actual.append(relative)
        identity = (info.st_dev, info.st_ino)
        if identity in identities:
            reject("contains a hard-link or file-identity alias")
        identities[identity] = relative
expected_actual = ["packet.json"] + [path for path, unused_hash in entries]
if sorted(actual, key=lambda value: value.encode("ascii")) != sorted(expected_actual, key=lambda value: value.encode("ascii")):
    reject("regular-file set does not exactly match packet.json plus allowlist")

entry_map = dict(entries)
for relative, expected_hash in entries:
    staged = ensure_plain_path(packet_root, relative)
    if sha_file(staged) != expected_hash:
        reject("staged payload hash mismatch: " + relative)

def load_ndjson(relative):
    path = ensure_plain_path(packet_root, relative)
    raw = open(path, "rb").read()
    if not raw or not raw.endswith(b"\n") or b"\n\n" in raw:
        reject(relative + " is not complete newline-terminated NDJSON")
    values = []
    for line_no, line in enumerate(raw.splitlines(), 1):
        try:
            text = line.decode("utf-8")
            value = json.loads(
                text,
                object_pairs_hook=pairs_object,
                parse_constant=lambda value: reject("NDJSON contains non-RFC-8259 constant: " + value),
            )
        except (UnicodeDecodeError, ValueError, json.JSONDecodeError) as exc:
            reject("invalid %s line %d: %s" % (relative, line_no, exc))
        if not isinstance(value, dict):
            reject("%s line %d is not an object" % (relative, line_no))
        values.append(value)
    return values

# The closed coverage ledger defines the only dynamic packet members.
coverage_events = load_ndjson("audit/coverage-index.ndjson")
coverage_paths = []
coverage_pairs = []
seen_domains = set()
for index, event in enumerate(coverage_events, 1):
    if event.get("sequence") != index or type(event.get("sequence")) is not int:
        reject("coverage ledger sequence is not contiguous")
    if event.get("event") == "coverage-completed":
        exact_keys(event, ["schema_version", "event", "sequence", "domain_id", "coverage_path",
                           "coverage_sha256", "reviewer_attempt_id", "recorded_at"], "coverage event")
        if event["schema_version"] != 1 or type(event["schema_version"]) is not int:
            reject("coverage event schema_version is invalid")
        safe_id(event["domain_id"], "coverage domain_id")
        safe_id(event["reviewer_attempt_id"], "coverage reviewer_attempt_id")
        valid_timestamp(event["recorded_at"], "coverage recorded_at")
        expected_path = "audit/coverage/%s.md" % event["domain_id"]
        if event["coverage_path"] != expected_path or event["domain_id"] in seen_domains:
            reject("coverage event path/domain binding is invalid")
        if not isinstance(event["coverage_sha256"], str) or SHA256.fullmatch(event["coverage_sha256"]) is None:
            reject("coverage event hash is invalid")
        seen_domains.add(event["domain_id"])
        coverage_paths.append(expected_path)
        coverage_pairs.append({"path": expected_path, "sha256": event["coverage_sha256"]})
    elif event.get("event") == "coverage-closed":
        exact_keys(event, ["schema_version", "event", "sequence", "closure_reason", "domain_register_path",
                           "domain_register_sha256", "completed_count", "completed_set_sha256", "recorded_at"],
                   "coverage closure")
        if index != len(coverage_events):
            reject("coverage closure is not terminal")
        if event["schema_version"] != 1 or type(event["schema_version"]) is not int:
            reject("coverage closure schema_version is invalid")
        if event["closure_reason"] not in {"all-applicable-completed", "unresolved-intent",
                                           "all-domains-excluded", "partial-coverage-archival"}:
            reject("coverage closure reason is invalid")
        if event["domain_register_path"] != "audit/domain-register.md":
            reject("coverage closure domain register path is invalid")
        if event["domain_register_sha256"] != entry_map.get("audit/domain-register.md"):
            reject("coverage closure domain register hash is invalid")
        if type(event["completed_count"]) is not int or event["completed_count"] != len(coverage_paths):
            reject("coverage closure completed_count is invalid")
        canonical = json.dumps(sorted(coverage_pairs, key=lambda item: item["path"].encode("ascii")),
                               ensure_ascii=True, separators=(",", ":")).encode("utf-8")
        if event["completed_set_sha256"] != hashlib.sha256(canonical).hexdigest():
            reject("coverage closure completed-set hash is invalid")
        valid_timestamp(event["recorded_at"], "coverage closure recorded_at")
    else:
        reject("coverage ledger contains an unknown event")
if not coverage_events or coverage_events[-1].get("event") != "coverage-closed":
    reject("coverage ledger is not closed")
for pair in coverage_pairs:
    if entry_map.get(pair["path"]) != pair["sha256"]:
        reject("coverage ledger member/hash is not bound to allowlist: " + pair["path"])

reservation_path = "audit/versions/%s/reservation.json" % audit_version
required = {
    "audit/profile.md", "audit/product-contract.md", "audit/domain-register.md",
    "audit/coverage-index.ndjson", "audit/runtime-verification.md", "audit/setup-quarantine.md",
    reservation_path, "audit/version-index.ndjson", expected_corrected,
    "docs/codebase-readiness-audit-contract.md", "workflows/codebase-readiness-audit.md",
    "agents/critic/readiness-audit.md",
}
required.update(coverage_paths)
if set(entry_map) != required:
    reject("allowlist does not equal the contract-required packet member set")

reservation, unused = load_json_bytes(ensure_plain_path(packet_root, reservation_path))
exact_keys(reservation, ["schema_version", "audit_version", "allocation_id",
                         "reconciliation_attempt_id", "reserved_at"], "reservation")
if type(reservation["schema_version"]) is not int or reservation["schema_version"] != 1:
    reject("reservation schema_version is invalid")
if reservation["audit_version"] != audit_version:
    reject("reservation audit_version binding is invalid")
safe_id(reservation["allocation_id"], "reservation allocation_id")
safe_id(reservation["reconciliation_attempt_id"], "reservation reconciliation_attempt_id")
valid_timestamp(reservation["reserved_at"], "reservation reserved_at")

version_events = load_ndjson("audit/version-index.ndjson")
matching = []
for event in version_events:
    if event.get("event") == "corrected" and event.get("audit_version") == audit_version:
        exact_keys(event, ["schema_version", "audit_version", "event", "artifact_path",
                           "artifact_sha256", "recorded_at"], "corrected index event")
        matching.append(event)
if len(matching) != 1:
    reject("version index lacks exactly one corrected event for audit_version")
corrected_event = matching[0]
if (type(corrected_event["schema_version"]) is not int or corrected_event["schema_version"] != 1 or
        corrected_event["artifact_path"] != expected_corrected or
        corrected_event["artifact_sha256"] != entry_map[expected_corrected] or
        not isinstance(corrected_event["artifact_sha256"], str) or
        SHA256.fullmatch(corrected_event["artifact_sha256"]) is None):
    reject("corrected index event path/hash binding is invalid")
valid_timestamp(corrected_event["recorded_at"], "corrected event recorded_at")

# Every packet member is rebound to its immutable authoritative source.
framework_members = {
    "docs/codebase-readiness-audit-contract.md",
    "workflows/codebase-readiness-audit.md",
    "agents/critic/readiness-audit.md",
}
for relative, expected_hash in entries:
    source_root = framework_root if relative in framework_members else run_dir
    source = ensure_plain_path(source_root, relative)
    if sha_file(source) != expected_hash:
        reject("authoritative source hash mismatch: " + relative)
    staged_info = os.lstat(ensure_plain_path(packet_root, relative))
    source_info = os.lstat(source)
    if (staged_info.st_dev, staged_info.st_ino) == (source_info.st_dev, source_info.st_ino):
        reject("staged payload aliases its authoritative source: " + relative)

expected_packet_root = os.path.join(run_dir, "audit", "reviews", manifest["attempt_id"] + "-packet")
if packet_root != expected_packet_root or os.path.realpath(packet_root) != os.path.realpath(expected_packet_root):
    reject("root is not the attempt-bound canonical packet directory")
for parent in [os.path.join(run_dir, "audit"), os.path.join(run_dir, "audit", "reviews"),
               os.path.join(run_dir, "verdicts")]:
    try:
        mode = os.lstat(parent).st_mode
    except OSError as exc:
        reject("required output parent is missing: %s" % exc)
    if stat.S_ISLNK(mode) or not stat.S_ISDIR(mode):
        reject("output parent is not a regular directory: " + parent)

reviews_parent = os.path.join(run_dir, "audit", "reviews")
result_name = manifest["attempt_id"] + "-result"
verdict_name = manifest["attempt_id"] + ".json"
for parent, target_name, label in [(reviews_parent, result_name, "result"),
                                    (os.path.join(run_dir, "verdicts"), verdict_name, "canonical verdict")]:
    matches = []
    for existing in os.listdir(parent):
        if existing == target_name or existing.lower() == target_name.lower():
            matches.append(existing)
    if label == "result" and validation_phase == "after":
        if matches != [target_name]:
            reject("reserved result directory is missing or case-colliding")
        result_path = os.path.join(parent, target_name)
        info = os.lstat(result_path)
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode) or os.listdir(result_path):
            reject("reserved result directory is not an empty regular directory")
    elif matches:
        reject(label + " path collides with an existing object")

state = {
    "manifest_sha256": hashlib.sha256(manifest_raw).hexdigest(),
    "attempt_id": manifest["attempt_id"],
    "output_id": manifest["output_id"],
    "audit_version": audit_version,
    "corrected_audit_path": expected_corrected,
    "corrected_audit_sha256": entry_map[expected_corrected],
    "review_question": manifest["review_question"],
    "allowlist": manifest["allowlist"],
}
with open(state_out, "w", encoding="utf-8") as handle:
    json.dump(state, handle, ensure_ascii=True, separators=(",", ":"), sort_keys=True)
    handle.write("\n")
PY
  }

  validate_readiness_packet "$packet_state_before" before || exit 1
  attempt_id="$(jq -er '.attempt_id' "$packet_state_before")" || fail "cannot read validated attempt_id"
  output_id="$(jq -er '.output_id' "$packet_state_before")" || fail "cannot read validated output_id"
  result_dir="$RUN_DIR/audit/reviews/${attempt_id}-result"
  canonical_verdict="$RUN_DIR/verdicts/${attempt_id}.json"
  mkdir "$result_dir" 2>/dev/null || fail "cannot exclusively reserve readiness result directory: $result_dir"

  runtime="${BUREAU_REVIEWER_HOST:-}"
  if [ -z "$runtime" ] && [ -f "$ROUTING" ]; then
    runtime="$(jq -r '.runtime // empty' "$ROUTING" 2>/dev/null)"
  fi
  [ -n "$runtime" ] || runtime="claude"
  case "$runtime" in
    openai|codex) runtime="openai" ;;
    claude) ;;
    *) fail "reviewer host '$runtime' has no cold-reviewer adapter" ;;
  esac

  model=""
  reasoning_effort=""
  if [ -f "$ROUTING" ]; then
    model="$(jq -r '.roles.challenger.model // empty' "$ROUTING" 2>/dev/null)"
    reasoning_effort="$(jq -r '.roles.challenger.reasoningEffort // empty' "$ROUTING" 2>/dev/null)"
  fi
  if [ "$runtime" = "claude" ]; then
    [ -n "$model" ] || model="opus"
  else
    [ -n "$model" ] || model="gpt-5.6-sol"
    [ -n "$reasoning_effort" ] || reasoning_effort="high"
  fi

  candidate_schema="$readiness_tmp/candidate-schema.json"
  jq '
    del(.properties.verdict, .properties.timestamp)
    | .required = ["attempt_id", "review_mode", "reviewed_artifacts", "blocker_ids", "blockers", "warnings"]
    | .properties.reviewed_artifacts.items = .properties.reviewed_artifacts.items.oneOf[0]
    | .properties.blockers.items.additionalProperties = false
    | .properties.warnings.items.additionalProperties = false
  ' "$readiness_schema" > "$candidate_schema" \
    || fail "cannot derive readiness candidate schema"

  build_readiness_prompt() {
    prompt_root="$1"
    question="$(jq -r '.review_question' "$packet_state_before")"
    printf '%s' "You are The Challenger performing an isolated Codebase Readiness Audit verification. Read ${prompt_root}/packet.json, then read only the regular packet-relative payload files in its allowlist beneath ${prompt_root}. Do not open any path absent from that allowlist, use network access, or seek live run, repository, framework, home, configuration, or session data. Apply the staged self-contained readiness reviewer slice and answer this bounded question: ${question} Return only the exact six-field structured candidate described by the packet contract; do not include verdict or timestamp and do not write any file."
  }

  extract_claude_candidate() {
    raw="$1"
    out="$2"
    if jq -e 'type == "object" and has("attempt_id")' "$raw" >/dev/null 2>&1; then
      cp "$raw" "$out"
    elif jq -e '.structured_output | type == "object"' "$raw" >/dev/null 2>&1; then
      jq -c '.structured_output' "$raw" > "$out"
    elif jq -e '.result | type == "object"' "$raw" >/dev/null 2>&1; then
      jq -c '.result' "$raw" > "$out"
    elif jq -e '.result | type == "string"' "$raw" >/dev/null 2>&1; then
      jq -r '.result' "$raw" > "$out"
    else
      return 1
    fi
  }

  provider_candidate="$readiness_tmp/provider-candidate.json"
  provider_stderr="$readiness_tmp/provider-stderr.log"
  if [ "$runtime" = "claude" ]; then
    claude_bin="${CLAUDE_BIN:-claude}"
    command -v "$claude_bin" >/dev/null 2>&1 || fail "Claude CLI not found: $claude_bin"
    task_prompt="$(build_readiness_prompt "$CTX")"
    raw_claude="$readiness_tmp/claude-raw.json"
    system_prompt="You are The Challenger in readiness-audit verification mode. The staged packet is your entire review world. Do not load CLAUDE.md or act as the Conductor."
    budget="${CHALLENGER_MAX_USD:-${DELEGATE_MAX_USD:-5.00}}"
    (
      cd "$CTX" &&
      "$claude_bin" -p \
        --system-prompt "$system_prompt" \
        --model "$model" \
        --output-format json \
        --json-schema "$(cat "$candidate_schema")" \
        --tools "Read" \
        --add-dir "$CTX" \
        --setting-sources "" \
        --no-session-persistence \
        --max-budget-usd "$budget" \
        "$task_prompt" < /dev/null
    ) > "$raw_claude" 2> "$provider_stderr"
    cli_rc=$?
    [ "$cli_rc" -eq 0 ] || fail "Claude readiness reviewer exited $cli_rc"
    extract_claude_candidate "$raw_claude" "$provider_candidate" \
      || fail "Claude readiness reviewer returned no structured candidate"
  else
    codex_bin="${CODEX_BIN:-codex}"
    command -v "$codex_bin" >/dev/null 2>&1 || fail "Codex CLI not found: $codex_bin"
    snap_root="$readiness_tmp/codex-snapshot"
    mkdir "$snap_root" || fail "cannot create isolated Codex snapshot"
    snap_ctx="$snap_root/staged"
    mkdir -p "$snap_ctx" || fail "cannot create isolated Codex context"
    cp -R "$CTX/." "$snap_ctx/" || fail "cannot copy staged context into isolated Codex snapshot"
    snap_ctx="$(cd "$snap_ctx" && pwd -P)" || fail "cannot resolve isolated Codex context"

    fs_rules='":minimal"="read",":workspace_roots"={"."="read"}'
    append_readiness_deny() {
      deny_path="$1"
      [ -n "$deny_path" ] || return 0
      quoted="$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$deny_path")"
      case ",$fs_rules," in
        *,"$quoted"'="deny"',*) return 0 ;;
      esac
      fs_rules="${fs_rules},${quoted}=\"deny\""
    }
    append_readiness_deny "$RUN_DIR"
    append_readiness_deny "$CTX"
    append_readiness_deny "$ROOT"
    append_readiness_deny "${HOME:-}"
    append_readiness_deny "${CODEX_HOME:-${HOME:-}/.codex}"
    append_readiness_deny "${HOME:-}/.claude"
    append_readiness_deny "${HOME:-}/.novadiem"
    target_repo="$(jq -r '.target_repo // empty' "$RUN_DIR/state.json" 2>/dev/null)"
    case "$target_repo" in
      /*) append_readiness_deny "$target_repo" ;;
    esac
    append_readiness_deny "${BUREAU_REVIEWER_UNSTAGED_SENTINEL:-}"
    append_readiness_deny "${UNSTAGED_SENTINEL:-}"

    permissions="{bureau-review={filesystem={${fs_rules}},network={enabled=false}}}"
    task_prompt="$(build_readiness_prompt "$snap_ctx")"
    last_message="$readiness_tmp/last-message.json"
    provider_events="$readiness_tmp/provider-events.jsonl"
    "$codex_bin" --ask-for-approval never exec \
      --ephemeral \
      --ignore-user-config \
      --ignore-rules \
      --skip-git-repo-check \
      --color never \
      -C "$snap_ctx" \
      -m "$model" \
      -c "model_reasoning_effort=\"$reasoning_effort\"" \
      -c 'default_permissions="bureau-review"' \
      -c "permissions=$permissions" \
      --output-schema "$candidate_schema" \
      -o "$last_message" \
      --json \
      "$task_prompt" \
      > "$provider_events" \
      2> "$provider_stderr"
    cli_rc=$?
    [ "$cli_rc" -eq 0 ] || fail "Codex readiness reviewer exited $cli_rc"
    [ -s "$last_message" ] || fail "Codex readiness reviewer returned no final candidate"
    cp "$last_message" "$provider_candidate" || fail "cannot retain Codex readiness candidate"
  fi

  validate_readiness_packet "$packet_state_after" after || exit 1
  cmp -s "$packet_state_before" "$packet_state_after" \
    || fail "readiness packet or authoritative binding changed during provider invocation"
  [ ! -e "$canonical_verdict" ] && [ ! -L "$canonical_verdict" ] \
    || fail "canonical readiness verdict collided after provider invocation"
  if find "$result_dir" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
    fail "reserved readiness result directory was modified before adapter publication"
  fi

  candidate_bytes="$readiness_tmp/validated-candidate.json"
  canonical_bytes="$readiness_tmp/canonical-verdict.json"
  python3 - "$provider_candidate" "$packet_state_before" "$readiness_schema" \
    "$candidate_bytes" "$canonical_bytes" <<'PY'
import datetime
import json
import re
import sys
import unicodedata

candidate_path, state_path, schema_path, candidate_out, canonical_out = sys.argv[1:]

def reject(message):
    raise SystemExit("run-cold-reviewer: readiness candidate " + message)

def pairs_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            reject("contains duplicate JSON key: " + key)
        result[key] = value
    return result

def load(path):
    raw = open(path, "rb").read()
    if raw.startswith(b"\xef\xbb\xbf"):
        reject("contains a byte order mark")
    try:
        text = raw.decode("utf-8")
        decoder = json.JSONDecoder(
            object_pairs_hook=pairs_object,
            parse_constant=lambda value: reject("contains non-RFC-8259 constant: " + value),
        )
        value, end = decoder.raw_decode(text)
    except (UnicodeDecodeError, ValueError, json.JSONDecodeError) as exc:
        reject("is invalid JSON: %s" % exc)
    if text[end:].strip():
        reject("contains trailing JSON content")
    return value, raw

def exact_keys(value, keys, label):
    if not isinstance(value, dict) or set(value) != set(keys):
        reject(label + " has the wrong exact key set")

SAFE_ID = re.compile(rb"[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?")

def safe_id(value, label):
    if not isinstance(value, str):
        reject(label + " is not a string")
    try:
        raw = value.encode("ascii")
    except UnicodeEncodeError:
        reject(label + " is not ASCII")
    if SAFE_ID.fullmatch(raw) is None:
        reject(label + " is malformed")

def bounded(value, limit, label):
    if not isinstance(value, str) or not 1 <= len(value.encode("utf-8")) <= limit:
        reject(label + " is empty or over limit")
    if any(unicodedata.category(ch) == "Cc" for ch in value):
        reject(label + " contains a control character")

candidate, candidate_raw = load(candidate_path)
state, unused = load(state_path)
schema, unused = load(schema_path)
exact_keys(candidate, ["attempt_id", "review_mode", "reviewed_artifacts", "blocker_ids", "blockers", "warnings"],
           "object")
if candidate["attempt_id"] != state["attempt_id"]:
    reject("attempt_id does not match packet")
safe_id(candidate["attempt_id"], "attempt_id")
if candidate["review_mode"] != "verification":
    reject("review_mode is not verification")
if candidate["reviewed_artifacts"] != state["allowlist"]:
    reject("reviewed_artifacts does not exactly match ordered packet allowlist")
if not isinstance(candidate["blockers"], list) or not isinstance(candidate["blocker_ids"], list):
    reject("blockers and blocker_ids must be arrays")
if not isinstance(candidate["warnings"], list):
    reject("warnings must be an array")

all_ids = set()
blocker_ids = []
allowed_paths = {item["path"] for item in state["allowlist"]}
for index, blocker in enumerate(candidate["blockers"]):
    exact_keys(blocker, ["id", "summary", "citation"], "blocker[%d]" % index)
    safe_id(blocker["id"], "blocker id")
    bounded(blocker["summary"], 1000, "blocker summary")
    if blocker["id"] in all_ids:
        reject("contains a duplicate or colliding blocker id")
    all_ids.add(blocker["id"])
    blocker_ids.append(blocker["id"])
    citation = blocker["citation"]
    if not isinstance(citation, dict) or citation.get("kind") not in {"presence", "absence"}:
        reject("blocker citation kind is invalid")
    if citation["kind"] == "presence":
        exact_keys(citation, ["kind", "path", "anchor"], "presence citation")
        bounded(citation["anchor"], 1000, "citation anchor")
    else:
        exact_keys(citation, ["kind", "path", "missing"], "absence citation")
        bounded(citation["missing"], 1000, "citation missing")
    if citation["path"] not in allowed_paths:
        reject("citation path is absent from reviewed_artifacts")
if candidate["blocker_ids"] != blocker_ids:
    reject("blocker_ids does not exactly repeat blockers[].id in order")
for index, warning in enumerate(candidate["warnings"]):
    exact_keys(warning, ["id", "summary"], "warning[%d]" % index)
    safe_id(warning["id"], "warning id")
    bounded(warning["summary"], 1000, "warning summary")
    if warning["id"] in all_ids:
        reject("contains a duplicate or cross-category colliding id")
    all_ids.add(warning["id"])

if candidate["blocker_ids"]:
    verdict = "BLOCKED"
elif candidate["warnings"]:
    verdict = "APPROVED_WITH_WARNINGS"
else:
    verdict = "APPROVED"
canonical = dict(candidate)
canonical["verdict"] = verdict
canonical["timestamp"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

# Require the selected canonical schema to expose the exact standard verdict
# fields and accept the values this adapter derives.
expected_fields = {"attempt_id", "review_mode", "reviewed_artifacts", "blocker_ids",
                   "blockers", "warnings", "verdict", "timestamp"}
if set(schema.get("required", [])) != expected_fields or set(schema.get("properties", {})) != expected_fields:
    reject("selected Challenger verdict schema does not expose the expected exact field set")
if canonical["review_mode"] not in schema["properties"]["review_mode"].get("enum", []):
    reject("review_mode is not valid under selected Challenger verdict schema")
if canonical["verdict"] not in schema["properties"]["verdict"].get("enum", []):
    reject("derived verdict is not valid under selected Challenger verdict schema")

with open(candidate_out, "wb") as handle:
    handle.write(candidate_raw)
with open(canonical_out, "w", encoding="utf-8") as handle:
    json.dump(canonical, handle, ensure_ascii=True, separators=(",", ":"), sort_keys=False)
    handle.write("\n")
PY

  publish_no_clobber() {
    source_path="$1"
    target_path="$2"
    python3 - "$source_path" "$target_path" <<'PY'
import os
import secrets
import sys

source, target = sys.argv[1:]
parent = os.path.dirname(target)
name = os.path.basename(target)
for existing in os.listdir(parent):
    if existing == name or existing.lower() == name.lower():
        raise SystemExit("run-cold-reviewer: no-clobber publication collision: " + target)
temporary = os.path.join(parent, ".readiness-publish-%s.tmp" % secrets.token_hex(12))
flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
descriptor = os.open(temporary, flags, 0o600)
try:
    with os.fdopen(descriptor, "wb") as handle:
        handle.write(open(source, "rb").read())
        handle.flush()
        os.fsync(handle.fileno())
    os.link(temporary, target)
    directory = os.open(parent, os.O_RDONLY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)
finally:
    try:
        os.unlink(temporary)
    except FileNotFoundError:
        pass
PY
  }

  candidate_path="$result_dir/${output_id}.json"
  publish_no_clobber "$candidate_bytes" "$candidate_path" || exit 1
  publish_no_clobber "$canonical_bytes" "$canonical_verdict" || exit 1
  jq -cn \
    --arg runtime "$runtime" \
    --arg model "$model" \
    --arg reasoning_effort "$reasoning_effort" \
    --arg verdict_path "$canonical_verdict" \
    --arg candidate_path "$candidate_path" \
    --arg result_dir "$result_dir" \
    '{
      runtime: $runtime,
      model: $model,
      reasoning_effort: (if $reasoning_effort == "" then null else $reasoning_effort end),
      verdict_path: $verdict_path,
      candidate_path: $candidate_path,
      result_dir: $result_dir
    }'
}

# Readiness owns a distinct closed-packet/result contract. Dispatch it before
# any Delegate-only schema, argument, required-file, model, cleanup, prompt, or
# verdict assumption below.
if [ "$REVIEW_MODE" = "readiness-audit" ]; then
  run_readiness_audit
  exit $?
fi

SCHEMA="$ROOT/config/delegate-verdict.schema.json"
CODEX_SCHEMA="$ROOT/config/delegate-verdict.codex.schema.json"
CHECKPOINTS_DIR="$RUN_DIR/checkpoints"

[ -d "$RUN_DIR" ] || fail "RUN_DIR is not a directory: $RUN_DIR"
[ -d "$CTX" ] || fail "CTX is not a directory: $CTX"
[ -f "$SCHEMA" ] || fail "verdict schema not found: $SCHEMA"
[ -f "$CODEX_SCHEMA" ] || fail "Codex verdict schema not found: $CODEX_SCHEMA"

case "$CHECKPOINT" in
  *[!0-9]*|'') fail "checkpoint must contain only digits: $CHECKPOINT" ;;
esac
case "$SPAWN_ID" in
  *[!A-Za-z0-9._-]*|'') fail "spawn-id contains unsafe characters: $SPAWN_ID" ;;
esac
case "$ARTIFACT_BASE" in
  */*|''|.|..) fail "artifact-basename must be one safe basename: $ARTIFACT_BASE" ;;
esac
case "$REVIEW_MODE" in
  routine|integration) ;;
  *) fail "review mode must be routine or integration: $REVIEW_MODE" ;;
esac

CTX="$(cd "$CTX" && pwd -P)" || fail "cannot resolve CTX"
RUN_DIR="$(cd "$RUN_DIR" && pwd -P)" || fail "cannot resolve RUN_DIR"
CHECKPOINTS_DIR="$RUN_DIR/checkpoints"
mkdir -p "$CHECKPOINTS_DIR" || fail "cannot create checkpoints directory"

for required in \
  "$CTX/delegate-reviewer.md" \
  "$CTX/conventions.md" \
  "$CTX/log-slice.md" \
  "$CTX/state.json" \
  "$CTX/$ARTIFACT_BASE"
do
  [ -f "$required" ] || fail "staged reviewer file missing: $required"
done
if [ "$REVIEW_MODE" = "integration" ] && [ ! -f "$CTX/integration-results.json" ]; then
  fail "integration review requires staged integration-results.json"
fi

# Symlinks can point through an otherwise-correct staged root. Reject the whole
# packet rather than trying to reason about each target.
if find "$CTX" -type l -print -quit 2>/dev/null | grep -q .; then
  fail "staged context contains a symlink"
fi
if find "$CTX" -type f \( -name 'log.md' -o -iname '*transcript*' \) -print -quit 2>/dev/null | grep -q .; then
  fail "staged context contains a forbidden full-log or transcript-like file"
fi

RUNTIME="${BUREAU_REVIEWER_HOST:-}"
if [ -z "$RUNTIME" ] && [ -f "$ROUTING" ]; then
  RUNTIME="$(jq -r '.runtime // empty' "$ROUTING" 2>/dev/null)"
fi
[ -n "$RUNTIME" ] || RUNTIME="claude"
case "$RUNTIME" in
  openai|codex) RUNTIME="openai" ;;
  claude) ;;
  *) fail "reviewer host '$RUNTIME' has no cold-reviewer adapter" ;;
esac

MODEL=""
REASONING_EFFORT=""
if [ -f "$ROUTING" ]; then
  MODEL="$(jq -r '.roles.delegate.model // empty' "$ROUTING" 2>/dev/null)"
  REASONING_EFFORT="$(jq -r '.roles.delegate.reasoningEffort // empty' "$ROUTING" 2>/dev/null)"
fi
if [ "$RUNTIME" = "claude" ]; then
  [ -n "$MODEL" ] || MODEL="opus"
else
  [ -n "$MODEL" ] || MODEL="gpt-5.6-sol"
  [ -n "$REASONING_EFFORT" ] || REASONING_EFFORT="high"
fi

VERDICT_PATH="$CHECKPOINTS_DIR/${SPAWN_ID}-reviewer-verdict.json"
ENVELOPE_PATH="$CHECKPOINTS_DIR/${SPAWN_ID}-reviewer-envelope.json"
EVENTS_PATH="$CHECKPOINTS_DIR/${SPAWN_ID}-reviewer-events.jsonl"
STDERR_PATH="$CHECKPOINTS_DIR/${SPAWN_ID}-reviewer-stderr.log"

rm -f "$VERDICT_PATH" "$ENVELOPE_PATH" "$EVENTS_PATH" "$STDERR_PATH"

build_task_prompt() {
  prompt_ctx="$1"
  prompt_artifact="$2"
  if [ "$REVIEW_MODE" = "integration" ]; then
    printf '%s' "You are reviewing checkpoint ${CHECKPOINT} as The Delegate cold reviewer. Read only these staged files: ${prompt_ctx}/delegate-reviewer.md (your role and critic checklist), ${prompt_ctx}/conventions.md (the convention router; load only a needed module from ${prompt_ctx}/conventions/), ${prompt_ctx}/log-slice.md (this checkpoint's slice only), ${prompt_ctx}/state.json (run state), ${prompt_ctx}/${prompt_artifact} (the artifact), and ${prompt_ctx}/integration-results.json (canonical gate results). Apply the verifying-mode checklist and return only a verdict JSON conforming to the supplied schema, including Integration-evidence. Do not look for log.md; it is intentionally unavailable. If a full log or session transcript appears, stop and return an escalate verdict describing the coldness breach."
  else
    printf '%s' "You are reviewing checkpoint ${CHECKPOINT} as The Delegate cold reviewer. Read only these staged files: ${prompt_ctx}/delegate-reviewer.md (your role and critic checklist), ${prompt_ctx}/conventions.md (the convention router; load only a needed module from ${prompt_ctx}/conventions/), ${prompt_ctx}/log-slice.md (this checkpoint's slice only), ${prompt_ctx}/state.json (run state), and ${prompt_ctx}/${prompt_artifact} (the artifact). Apply the critic checklist and return only a verdict JSON conforming to the supplied schema. This is a routine checkpoint, so set Integration-evidence to null when the schema requires that field. Do not look for log.md; it is intentionally unavailable. If a full log or session transcript appears, stop and return an escalate verdict describing the coldness breach."
  fi
}

audit_task_prompt() {
  audit_runtime="$1"
  audit_prompt="$2"
  bash "$SCRIPT_DIR/log-append.sh" "$RUN_DIR" \
    "Cold reviewer prompt — spawn: $SPAWN_ID, runtime: $audit_runtime, prompt: $audit_prompt" \
    >/dev/null \
    || fail "cannot append cold-reviewer prompt audit line"
}

extract_claude_verdict() {
  raw="$1"
  out="$2"
  if jq -e 'type == "object" and has("Decision")' "$raw" >/dev/null 2>&1; then
    jq 'del(.usage, .num_turns, .type, .subtype, .duration_ms, .duration_api_ms, .is_error, .session_id, .total_cost_usd)' \
      "$raw" > "$out"
  elif jq -e '.structured_output | type == "object"' "$raw" >/dev/null 2>&1; then
    jq '.structured_output' "$raw" > "$out"
  elif jq -e '.result | type == "object"' "$raw" >/dev/null 2>&1; then
    jq '.result' "$raw" > "$out"
  elif jq -e '.result | type == "string"' "$raw" >/dev/null 2>&1; then
    jq -r '.result' "$raw" | jq '.' > "$out" 2>/dev/null
  else
    return 1
  fi
}

validate_verdict_shape() {
  jq -e '
    type == "object"
    and (.Decision == "proceed" or .Decision == "revise" or .Decision == "escalate")
    and (."Artifact-hash" | type == "string" and test("^[a-f0-9]{64}$"))
    and (.Uncertainties | type == "string" and length > 0)
    and (.Rationale | type == "string" and length > 0)
    and (."Required-changes" | type == "string" and length > 0)
    and (.Escalation | type == "string" and length > 0)
    and (.Ledger | type == "string" and length > 0)
  ' "$1" >/dev/null 2>&1
}

if [ "$RUNTIME" = "claude" ]; then
  CLAUDE_BIN="${CLAUDE_BIN:-claude}"
  command -v "$CLAUDE_BIN" >/dev/null 2>&1 || fail "Claude CLI not found: $CLAUDE_BIN"
  TASK_PROMPT="$(build_task_prompt "$CTX" "$ARTIFACT_BASE")"
  audit_task_prompt "$RUNTIME" "$TASK_PROMPT"
  RAW_CLAUDE="$CHECKPOINTS_DIR/${SPAWN_ID}-reviewer-claude-raw.json"
  SYSTEM_PROMPT="You are The Delegate cold reviewer. Do not load CLAUDE.md. Do not act as the Conductor."
  BUDGET="${DELEGATE_MAX_USD:-5.00}"

  (
    cd "$CTX" &&
    "$CLAUDE_BIN" -p \
      --system-prompt "$SYSTEM_PROMPT" \
      --model "$MODEL" \
      --output-format json \
      --json-schema "$(cat "$SCHEMA")" \
      --tools "Read" \
      --add-dir "$CTX" \
      --setting-sources "" \
      --no-session-persistence \
      --max-budget-usd "$BUDGET" \
      "$TASK_PROMPT" < /dev/null
  ) > "$RAW_CLAUDE" 2> "$STDERR_PATH"
  cli_rc=$?
  if [ "$cli_rc" -ne 0 ]; then
    fail "Claude reviewer exited $cli_rc (see $STDERR_PATH)"
  fi
  cp "$RAW_CLAUDE" "$ENVELOPE_PATH" || fail "cannot save Claude envelope"
  : > "$EVENTS_PATH"
  extract_claude_verdict "$RAW_CLAUDE" "$VERDICT_PATH" \
    || fail "Claude reviewer returned no structured verdict"
else
  CODEX_BIN="${CODEX_BIN:-codex}"
  command -v "$CODEX_BIN" >/dev/null 2>&1 || fail "Codex CLI not found: $CODEX_BIN"

  SNAP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/bureau-cold-review.XXXXXX")" \
    || fail "cannot create isolated Codex snapshot"
  cleanup_snapshot() {
    rm -rf "$SNAP_ROOT"
  }
  trap cleanup_snapshot EXIT
  SNAP_CTX="$SNAP_ROOT/staged"
  mkdir -p "$SNAP_CTX" || fail "cannot create isolated Codex context"
  cp -R "$CTX/." "$SNAP_CTX/" || fail "cannot copy staged context into isolated Codex snapshot"
  SNAP_CTX="$(cd "$SNAP_CTX" && pwd -P)" || fail "cannot resolve isolated Codex context"

  # Permission Profiles are most-specific-path wins. The temporary workspace is
  # read-only; the live run, target repo, framework, and conversation/config
  # stores are explicitly denied. Network tools are disabled. The model receives
  # snapshot paths only.
  fs_rules='":minimal"="read",":workspace_roots"={"."="read"}'
  append_deny() {
    deny_path="$1"
    [ -n "$deny_path" ] || return 0
    quoted="$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$deny_path")"
    case ",$fs_rules," in
      *,"$quoted"'="deny"',*) return 0 ;;
    esac
    fs_rules="${fs_rules},${quoted}=\"deny\""
  }

  append_deny "$RUN_DIR"
  append_deny "$CTX"
  append_deny "$ROOT"
  append_deny "${HOME:-}"
  append_deny "${CODEX_HOME:-${HOME:-}/.codex}"
  append_deny "${HOME:-}/.claude"
  append_deny "${HOME:-}/.novadiem"
  TARGET_REPO="$(jq -r '.target_repo // empty' "$RUN_DIR/state.json" 2>/dev/null)"
  case "$TARGET_REPO" in
    /*) append_deny "$TARGET_REPO" ;;
  esac

  PERMISSIONS="{bureau-review={filesystem={${fs_rules}},network={enabled=false}}}"
  TASK_PROMPT="$(build_task_prompt "$SNAP_CTX" "$ARTIFACT_BASE")"
  audit_task_prompt "$RUNTIME" "$TASK_PROMPT"
  LAST_MESSAGE="$SNAP_ROOT/last-message.json"

  "$CODEX_BIN" --ask-for-approval never exec \
    --ephemeral \
    --ignore-user-config \
    --ignore-rules \
    --skip-git-repo-check \
    --color never \
    -C "$SNAP_CTX" \
    -m "$MODEL" \
    -c "model_reasoning_effort=\"$REASONING_EFFORT\"" \
    -c 'default_permissions="bureau-review"' \
    -c "permissions=$PERMISSIONS" \
    --output-schema "$CODEX_SCHEMA" \
    -o "$LAST_MESSAGE" \
    --json \
    "$TASK_PROMPT" \
    > "$EVENTS_PATH" \
    2> "$STDERR_PATH"
  cli_rc=$?
  if [ "$cli_rc" -ne 0 ]; then
    fail "Codex reviewer exited $cli_rc (see $STDERR_PATH)"
  fi
  [ -s "$LAST_MESSAGE" ] || fail "Codex reviewer returned no final message"
  jq '.' "$LAST_MESSAGE" > "$VERDICT_PATH" 2>/dev/null \
    || fail "Codex reviewer final message was not JSON"

  jq -s --slurpfile verdict "$VERDICT_PATH" '
    [.[] | select(.type == "turn.completed")] as $turns
    | ($turns[-1].usage // {}) as $u
    | (($u.input_tokens // 0) | if type == "number" then . else 0 end) as $all_input
    | (($u.cached_input_tokens // 0) | if type == "number" then . else 0 end) as $cached
    | (($u.cache_write_input_tokens // 0) | if type == "number" then . else 0 end) as $cache_write
    | (($u.output_tokens // 0) | if type == "number" then . else 0 end) as $output
    | {
        type: "bureau-cold-review-result",
        runtime: "openai",
        result: $verdict[0],
        num_turns: ($turns | length),
        usage: {
          input_tokens: ([$all_input - $cached, 0] | max),
          cache_creation_input_tokens: $cache_write,
          cache_read_input_tokens: $cached,
          output_tokens: $output
        }
      }
      + (if ($turns | length) == 0
         then {_note: "Codex JSONL contained no turn.completed usage event"}
         else {} end)
  ' "$EVENTS_PATH" > "$ENVELOPE_PATH" 2>/dev/null \
    || fail "cannot normalize Codex reviewer usage envelope"
fi

validate_verdict_shape "$VERDICT_PATH" \
  || fail "reviewer verdict does not satisfy the required common shape"

jq -cn \
  --arg runtime "$RUNTIME" \
  --arg model "$MODEL" \
  --arg reasoning_effort "$REASONING_EFFORT" \
  --arg verdict_path "$VERDICT_PATH" \
  --arg envelope_path "$ENVELOPE_PATH" \
  --arg events_path "$EVENTS_PATH" \
  --arg stderr_path "$STDERR_PATH" \
  '{
    runtime: $runtime,
    model: $model,
    reasoning_effort: (if $reasoning_effort == "" then null else $reasoning_effort end),
    verdict_path: $verdict_path,
    envelope_path: $envelope_path,
    events_path: $events_path,
    stderr_path: $stderr_path
  }'
