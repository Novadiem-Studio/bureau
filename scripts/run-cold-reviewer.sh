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
    if [ -n "${custody_pid:-}" ]; then
      kill "$custody_pid" 2>/dev/null || true
      wait "$custody_pid" 2>/dev/null || true
    fi
    rm -rf "$readiness_tmp"
  }
  trap cleanup_readiness_tmp EXIT
  packet_state_before="$readiness_tmp/packet-before.json"
  packet_state_after="$readiness_tmp/packet-after.json"
  packet_state_final="$readiness_tmp/packet-final.json"

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
if validation_phase not in {"before", "after", "final"}:
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

read_bindings = {}

def read_plain_bytes(path):
    parent = os.path.dirname(path)
    try:
        parent_before = os.lstat(parent)
        path_before = os.lstat(path)
        flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0)
        descriptor = os.open(path, flags)
    except OSError as exc:
        reject("cannot securely open %s: %s" % (path, exc))
    try:
        opened_before = os.fstat(descriptor)
        if (stat.S_ISLNK(path_before.st_mode) or not stat.S_ISREG(path_before.st_mode) or
                not stat.S_ISREG(opened_before.st_mode) or path_before.st_nlink != 1 or
                opened_before.st_nlink != 1 or
                (path_before.st_dev, path_before.st_ino) !=
                (opened_before.st_dev, opened_before.st_ino)):
            reject("secure read target is not one exact unaliased regular file: " + path)
        chunks = []
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
        raw = b"".join(chunks)
        opened_after = os.fstat(descriptor)
    finally:
        os.close(descriptor)
    try:
        path_after = os.lstat(path)
        parent_after = os.lstat(parent)
    except OSError as exc:
        reject("secure read binding disappeared for %s: %s" % (path, exc))
    opened_identity = (opened_before.st_dev, opened_before.st_ino)
    if ((opened_after.st_dev, opened_after.st_ino) != opened_identity or
            opened_after.st_nlink != 1 or opened_after.st_size != len(raw) or
            (path_after.st_dev, path_after.st_ino) != opened_identity or
            path_after.st_nlink != 1 or not stat.S_ISREG(path_after.st_mode) or
            stat.S_ISLNK(parent_before.st_mode) or not stat.S_ISDIR(parent_before.st_mode) or
            (parent_after.st_dev, parent_after.st_ino) !=
            (parent_before.st_dev, parent_before.st_ino)):
        reject("secure read identity, bytes, link count, or parent changed: " + path)
    binding = {
        "dev": opened_after.st_dev,
        "ino": opened_after.st_ino,
        "parent_dev": parent_after.st_dev,
        "parent_ino": parent_after.st_ino,
        "sha256": hashlib.sha256(raw).hexdigest(),
        "size": len(raw),
    }
    absolute = os.path.abspath(path)
    if absolute in read_bindings and read_bindings[absolute] != binding:
        reject("secure read binding changed within validation: " + path)
    read_bindings[absolute] = binding
    return raw

def load_json_bytes(path):
    raw = read_plain_bytes(path)
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
        start = 0
        while start < len(text) and text[start] in " \t\r\n":
            start += 1
        value, end = decoder.raw_decode(text, start)
    except (ValueError, json.JSONDecodeError) as exc:
        reject("invalid JSON in %s: %s" % (path, exc))
    if any(character not in " \t\r\n" for character in text[end:]):
        reject("JSON has trailing content or non-RFC-8259 whitespace: " + path)
    return value, raw

def exact_keys(value, keys, label):
    if not isinstance(value, dict) or set(value) != set(keys):
        reject("%s has the wrong exact key set" % label)

SAFE_ID = re.compile(rb"[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?")
PATH_SEGMENT = re.compile(rb"[A-Za-z0-9](?:[A-Za-z0-9._-]{0,62}[A-Za-z0-9_-])?")
SHA256 = re.compile(r"[0-9a-f]{64}")
AUDIT_VERSION = re.compile(r"v(?:000[1-9]|00[1-9][0-9]|0[1-9][0-9]{2}|[1-9][0-9]{3})")
TIMESTAMP = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z")
DATE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}")

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
    try:
        size = len(value.encode("utf-8"))
    except UnicodeEncodeError:
        reject(label + " contains an invalid Unicode scalar value")
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
    return hashlib.sha256(read_plain_bytes(path)).hexdigest()

def ensure_plain_path(root, relative):
    current = root
    observed = []
    for segment in relative.split("/"):
        current = os.path.join(current, segment)
        try:
            info = os.lstat(current)
        except OSError as exc:
            reject("missing payload %s: %s" % (relative, exc))
        if stat.S_ISLNK(info.st_mode):
            reject("contains a symlink: " + relative)
        observed.append((current, info.st_dev, info.st_ino))
    try:
        common = os.path.commonpath([os.path.realpath(current), os.path.realpath(root)])
    except ValueError:
        reject("path escapes packet root: " + relative)
    final_info = os.lstat(current)
    if common != os.path.realpath(root) or not stat.S_ISREG(final_info.st_mode):
        reject("payload is not a regular file beneath the packet root: " + relative)
    if final_info.st_nlink != 1:
        reject("payload has an external hard-link alias: " + relative)
    for observed_path, expected_dev, expected_ino in observed:
        current_info = os.lstat(observed_path)
        if (current_info.st_dev, current_info.st_ino) != (expected_dev, expected_ino):
            reject("path identity changed during validation: " + relative)
    return current

run_dir = os.path.abspath(run_dir)
packet_root_raw = packet_root
if not os.path.isabs(packet_root_raw) or os.path.normpath(packet_root_raw) != packet_root_raw:
    reject("root must be an absolute, non-normalized path")
packet_root = packet_root_raw
packet_root_info = os.lstat(packet_root)
if stat.S_ISLNK(packet_root_info.st_mode) or not stat.S_ISDIR(packet_root_info.st_mode):
    reject("root is a symlink or not a directory")
packet_root_identity = (packet_root_info.st_dev, packet_root_info.st_ino)

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
directory_identities = {}
for current, directories, files in os.walk(packet_root, topdown=True, followlinks=False):
    current_info = os.lstat(current)
    if stat.S_ISLNK(current_info.st_mode) or not stat.S_ISDIR(current_info.st_mode):
        reject("contains a symlink or special directory entry")
    current_identity = (current_info.st_dev, current_info.st_ino)
    if current_identity in directory_identities:
        reject("contains a directory identity alias")
    directory_identities[current_identity] = current
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
        if identity in identities or info.st_nlink != 1:
            reject("contains a hard-link or file-identity alias")
        identities[identity] = relative
for identity, directory in directory_identities.items():
    current_info = os.lstat(directory)
    if stat.S_ISLNK(current_info.st_mode) or (current_info.st_dev, current_info.st_ino) != identity:
        reject("directory identity changed during packet enumeration")
current_packet_root = os.lstat(packet_root)
if (current_packet_root.st_dev, current_packet_root.st_ino) != packet_root_identity:
    reject("packet root identity changed during validation")
expected_actual = ["packet.json"] + [path for path, unused_hash in entries]
if sorted(actual, key=lambda value: value.encode("ascii")) != sorted(expected_actual, key=lambda value: value.encode("ascii")):
    reject("regular-file set does not exactly match packet.json plus allowlist")

entry_map = dict(entries)
for relative, expected_hash in entries:
    staged = ensure_plain_path(packet_root, relative)
    if sha_file(staged) != expected_hash:
        reject("staged payload hash mismatch: " + relative)

def compact_pairs(pairs, label):
    keys = [key for key, unused in pairs]
    try:
        raw_keys = [key.encode("ascii") for key in keys]
    except (AttributeError, UnicodeEncodeError):
        reject(label + " contains a non-ASCII object key")
    if raw_keys != sorted(raw_keys):
        reject(label + " object keys are not raw-ASCII sorted")
    return pairs_object(pairs)

def parse_compact_json_object(line, label):
    try:
        text = line.decode("utf-8")
    except UnicodeDecodeError:
        reject(label + " is not UTF-8")
    in_string = False
    escaped = False
    for character in text:
        if in_string:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
        elif character == '"':
            in_string = True
        elif character in " \t\r\n":
            reject(label + " contains whitespace outside a JSON string")
    try:
        value = json.loads(
            text,
            object_pairs_hook=lambda pairs: compact_pairs(pairs, label),
            parse_constant=lambda item: reject(label + " contains non-RFC-8259 constant: " + item),
        )
    except (ValueError, json.JSONDecodeError) as exc:
        reject(label + " is invalid JSON: %s" % exc)
    if not isinstance(value, dict):
        reject(label + " is not an object")
    return value

def load_ndjson(root, relative):
    path = ensure_plain_path(root, relative)
    raw = read_plain_bytes(path)
    if not raw or not raw.endswith(b"\n"):
        reject(relative + " is not complete newline-terminated NDJSON")
    values = []
    for line_no, line in enumerate(raw[:-1].split(b"\n"), 1):
        if not line:
            reject("%s line %d is blank" % (relative, line_no))
        values.append(parse_compact_json_object(line, "%s line %d" % (relative, line_no)))
    return values

def parse_domain_register(root, relative):
    path = ensure_plain_path(root, relative)
    raw = read_plain_bytes(path)
    if raw.startswith(b"\xef\xbb\xbf"):
        reject("domain register has a byte order mark")
    try:
        raw.decode("utf-8")
    except UnicodeDecodeError:
        reject("domain register is not UTF-8")
    heading = b"## Machine-readable domain register"
    opening = b"<!-- BEGIN CODEBASE-READINESS-DOMAIN-REGISTER v1 -->"
    closing = b"<!-- END CODEBASE-READINESS-DOMAIN-REGISTER v1 -->"
    lines = raw.splitlines()
    if (lines.count(heading) != 1 or lines.count(opening) != 1 or lines.count(closing) != 1 or
            raw.count(b"```json\n") != 1 or raw.count(b"\n```\n") != 1):
        reject("domain register lacks exactly one fixed heading and sentinel pair")
    start = raw.find(opening)
    end = raw.find(closing)
    heading_at = raw.find(heading)
    after_closing = end + len(closing)
    if (heading_at > start or end < start or (start and raw[start - 1:start] != b"\n") or
            (after_closing < len(raw) and raw[after_closing:after_closing + 1] != b"\n")):
        reject("domain register machine block order is invalid")
    between_heading = raw[heading_at + len(heading):start]
    if re.search(rb"(?:^|\n)## ", between_heading):
        reject("domain register machine block is not under the fixed heading")
    prefix = opening + b"\n```json\n"
    suffix = b"\n```\n" + closing
    if raw[start:start + len(prefix)] != prefix or raw[end - len(b"\n```\n"):end] != b"\n```\n":
        reject("domain register machine block delimiters are invalid")
    payload_start = start + len(prefix)
    payload_end = end - len(b"\n```\n")
    payload = raw[payload_start:payload_end]
    if not payload or b"\n" in payload or b"\r" in payload:
        reject("domain register machine payload is not exactly one nonempty line")
    if raw[start:end + len(closing)] != prefix + payload + suffix:
        reject("domain register machine block physical shape is invalid")
    try:
        text = payload.decode("utf-8")
        in_string = False
        escaped = False
        for character in text:
            if in_string:
                if escaped:
                    escaped = False
                elif character == "\\":
                    escaped = True
                elif character == '"':
                    in_string = False
            elif character == '"':
                in_string = True
            elif character in " \t\r\n":
                reject("domain register payload contains whitespace outside a JSON string")
        value = json.loads(
            text,
            object_pairs_hook=lambda pairs: compact_pairs(pairs, "domain register"),
            parse_constant=lambda item: reject("domain register contains non-RFC-8259 constant: " + item),
        )
    except (UnicodeDecodeError, ValueError, json.JSONDecodeError) as exc:
        reject("domain register machine payload is invalid JSON: %s" % exc)
    exact_keys(value, ["domains", "schema_version"], "domain register")
    if type(value["schema_version"]) is not int or value["schema_version"] != 1:
        reject("domain register schema_version is invalid")
    domains = value["domains"]
    if not isinstance(domains, list) or not domains:
        reject("domain register domains must be a nonempty array")
    baseline = {
        "architecture-scale": "architecture/scale",
        "code-health": "code health",
        "data-business-correctness": "data/business correctness",
        "feature-completeness": "feature completeness",
        "schema-drift-deploy": "schema/drift/deploy",
        "security-authorization": "security/authorization",
    }
    ids = []
    seen_aliases = set()
    applicable = set()
    excluded = set()
    for index, domain in enumerate(domains):
        if not isinstance(domain, dict) or domain.get("applicability") not in {"applicable", "excluded"}:
            reject("domain register member %d applicability is invalid" % index)
        expected_keys = (["applicability", "domain_id", "label"] if domain["applicability"] == "applicable"
                         else ["applicability", "domain_id", "exclusion_reason", "label"])
        exact_keys(domain, expected_keys, "domain register member %d" % index)
        safe_id(domain["domain_id"], "domain register domain_id")
        bounded_text(domain["label"], 200, "domain register label")
        if domain["label"] != domain["label"].strip():
            reject("domain register label has leading or trailing whitespace")
        domain_id = domain["domain_id"]
        alias = unicodedata.normalize("NFC", domain_id).casefold()
        if domain_id in ids or alias in seen_aliases:
            reject("domain register contains a duplicate or normalization/case alias ID")
        ids.append(domain_id)
        seen_aliases.add(alias)
        if domain_id in baseline and domain["label"] != baseline[domain_id]:
            reject("domain register baseline label is invalid: " + domain_id)
        if domain["applicability"] == "applicable":
            applicable.add(domain_id)
        else:
            bounded_text(domain["exclusion_reason"], 1000, "domain register exclusion_reason")
            if domain["exclusion_reason"] != domain["exclusion_reason"].strip():
                reject("domain register exclusion_reason has leading or trailing whitespace")
            excluded.add(domain_id)
    if ids != sorted(ids, key=lambda item: item.encode("ascii")):
        reject("domain register domains are not sorted by raw ASCII domain_id")
    if not set(baseline).issubset(set(ids)):
        reject("domain register lacks one or more mandatory baseline domains")
    return value, applicable, excluded, baseline

def validate_coverage_semantics(root, member_map):
    coverage_events = load_ndjson(root, "audit/coverage-index.ndjson")
    domain_register, applicable_ids, excluded_ids, baseline_domains = parse_domain_register(
        root, "audit/domain-register.md")
    coverage_paths = []
    coverage_pairs = []
    seen_domains = set()
    closure_reason = None
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
            closure_reason = event["closure_reason"]
            if event["domain_register_path"] != "audit/domain-register.md":
                reject("coverage closure domain register path is invalid")
            if (event["domain_register_sha256"] != member_map.get("audit/domain-register.md") or
                    event["domain_register_sha256"] != sha_file(ensure_plain_path(root, "audit/domain-register.md"))):
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
    completed_ids = set(seen_domains)
    if not completed_ids.issubset(applicable_ids):
        reject("coverage completion names an excluded or unknown domain")
    if closure_reason == "all-applicable-completed":
        if not completed_ids or completed_ids != applicable_ids:
            reject("all-applicable-completed does not exactly equal the nonempty applicable set")
    elif closure_reason == "partial-coverage-archival":
        if not completed_ids or not completed_ids < applicable_ids:
            reject("partial-coverage-archival is not a nonempty proper subset of applicable domains")
    elif closure_reason == "all-domains-excluded":
        if completed_ids or applicable_ids:
            reject("all-domains-excluded requires empty completed and applicable sets")
    elif closure_reason == "unresolved-intent":
        domains = domain_register["domains"]
        if (completed_ids or applicable_ids or len(domains) != 6 or set(excluded_ids) != set(baseline_domains) or
                any(domain.get("exclusion_reason") != "unresolved-intent" for domain in domains)):
            reject("unresolved-intent requires only six unresolved baseline exclusions and zero coverage")
    for pair in coverage_pairs:
        if (member_map.get(pair["path"]) != pair["sha256"] or
                sha_file(ensure_plain_path(root, pair["path"])) != pair["sha256"]):
            reject("coverage ledger member/hash is not bound to allowlist: " + pair["path"])
    return coverage_paths

# The closed coverage ledger defines the only dynamic packet members.
coverage_paths = validate_coverage_semantics(packet_root, entry_map)

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

def load_strict_version_index(path):
    raw = read_plain_bytes(path)
    if not raw or not raw.endswith(b"\n"):
        reject("version index is not nonempty complete newline-terminated NDJSON")
    events = []
    for line_no, line in enumerate(raw[:-1].split(b"\n"), 1):
        if not line:
            reject("version index line %d is blank" % line_no)
        events.append(parse_compact_json_object(line, "version index line %d" % line_no))
    return events

reservation_by_version = {}
allocation_owner = {}

def validate_authoritative_reservation(version):
    relative = "audit/versions/%s/reservation.json" % version
    value, unused = load_json_bytes(ensure_plain_path(run_dir, relative))
    exact_keys(value, ["schema_version", "audit_version", "allocation_id",
                       "reconciliation_attempt_id", "reserved_at"], "authoritative reservation")
    if type(value["schema_version"]) is not int or value["schema_version"] != 1:
        reject("authoritative reservation schema_version is invalid")
    if value["audit_version"] != version:
        reject("authoritative reservation version binding is invalid")
    safe_id(value["allocation_id"], "authoritative reservation allocation_id")
    safe_id(value["reconciliation_attempt_id"], "authoritative reservation reconciliation_attempt_id")
    valid_timestamp(value["reserved_at"], "authoritative reservation reserved_at")
    previous = reservation_by_version.get(version)
    if previous is not None and previous != value:
        reject("authoritative reservation changed across repeated validation")
    owner = allocation_owner.get(value["allocation_id"])
    if owner is not None and owner != version:
        reject("reservation allocation_id is reused by another audit version")
    reservation_by_version[version] = value
    allocation_owner[value["allocation_id"]] = version
    return value

def validate_historical_audited_review(version, corrected_hash, seal):
    verdict_relative = seal["cold_review_verdict_path"]
    match = re.fullmatch(r"verdicts/([a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?)\.json", verdict_relative)
    if match is None:
        reject("audited seal verdict path is invalid")
    attempt_id = match.group(1)
    safe_id(attempt_id, "historical audited attempt_id")
    verdict, verdict_raw = load_json_bytes(ensure_plain_path(run_dir, verdict_relative))
    verdict_keys = ["attempt_id", "review_mode", "reviewed_artifacts", "blocker_ids",
                    "blockers", "warnings", "verdict", "timestamp"]
    exact_keys(verdict, verdict_keys, "historical audited verdict")
    if verdict["attempt_id"] != attempt_id or verdict["review_mode"] != "verification":
        reject("historical audited verdict attempt/review-mode binding is invalid")
    valid_timestamp(verdict["timestamp"], "historical audited verdict timestamp")
    if not isinstance(verdict["reviewed_artifacts"], list) or not verdict["reviewed_artifacts"]:
        reject("historical audited verdict reviewed_artifacts is invalid")
    if not isinstance(verdict["blocker_ids"], list) or not isinstance(verdict["blockers"], list):
        reject("historical audited verdict blockers are invalid")
    if not isinstance(verdict["warnings"], list):
        reject("historical audited verdict warnings are invalid")
    allowed_paths = set()
    reviewed_paths = []
    for index, item in enumerate(verdict["reviewed_artifacts"]):
        exact_keys(item, ["path", "sha256"], "historical reviewed_artifacts[%d]" % index)
        raw_path = safe_packet_path(item["path"], "historical reviewed_artifacts path")
        if not isinstance(item["sha256"], str) or SHA256.fullmatch(item["sha256"]) is None:
            reject("historical reviewed_artifacts hash is invalid")
        if item["path"] in allowed_paths:
            reject("historical reviewed_artifacts contains a duplicate path")
        allowed_paths.add(item["path"])
        reviewed_paths.append(raw_path)
    if reviewed_paths != sorted(reviewed_paths):
        reject("historical reviewed_artifacts is not canonically sorted")
    all_ids = set()
    derived_blocker_ids = []
    for index, blocker in enumerate(verdict["blockers"]):
        exact_keys(blocker, ["id", "summary", "citation"], "historical blocker[%d]" % index)
        safe_id(blocker["id"], "historical blocker id")
        bounded_text(blocker["summary"], 1000, "historical blocker summary")
        if blocker["id"] in all_ids:
            reject("historical verdict contains duplicate or colliding IDs")
        all_ids.add(blocker["id"])
        derived_blocker_ids.append(blocker["id"])
        citation = blocker["citation"]
        if not isinstance(citation, dict) or citation.get("kind") not in {"presence", "absence"}:
            reject("historical blocker citation kind is invalid")
        if citation["kind"] == "presence":
            exact_keys(citation, ["kind", "path", "anchor"], "historical presence citation")
            bounded_text(citation["anchor"], 1000, "historical citation anchor")
        else:
            exact_keys(citation, ["kind", "path", "missing"], "historical absence citation")
            bounded_text(citation["missing"], 1000, "historical citation missing")
        if citation["path"] not in allowed_paths:
            reject("historical blocker citation path is absent from reviewed_artifacts")
    if verdict["blocker_ids"] != derived_blocker_ids:
        reject("historical blocker_ids does not exactly repeat blockers[].id")
    for index, warning in enumerate(verdict["warnings"]):
        exact_keys(warning, ["id", "summary"], "historical warning[%d]" % index)
        safe_id(warning["id"], "historical warning id")
        bounded_text(warning["summary"], 1000, "historical warning summary")
        if warning["id"] in all_ids:
            reject("historical verdict contains duplicate or cross-category colliding IDs")
        all_ids.add(warning["id"])
    derived_verdict = ("BLOCKED" if derived_blocker_ids else
                       "APPROVED_WITH_WARNINGS" if verdict["warnings"] else "APPROVED")
    if verdict["verdict"] != derived_verdict:
        reject("historical audited verdict value is not mechanically derived")
    if derived_verdict == "BLOCKED" or seal["cold_review_verdict"] != derived_verdict:
        reject("historical audited verdict is blocked or differs from the seal assertion")

    reviews_parent = os.path.join(run_dir, "audit", "reviews")
    expected_name = attempt_id + "-packet"
    matches = [name for name in os.listdir(reviews_parent) if name.lower() == expected_name.lower()]
    if matches != [expected_name]:
        reject("historical audited packet is missing, non-unique, or case-colliding")
    historical_root = os.path.join(reviews_parent, expected_name)
    mode = os.lstat(historical_root).st_mode
    if stat.S_ISLNK(mode) or not stat.S_ISDIR(mode):
        reject("historical audited packet root is a symlink or not a directory")
    manifest, unused = load_json_bytes(ensure_plain_path(historical_root, "packet.json"))
    manifest_keys = ["schema_version", "audit_version", "corrected_audit_path", "review_question",
                     "attempt_id", "output_id", "review_mode", "denied_inputs", "allowlist"]
    exact_keys(manifest, manifest_keys, "historical audited packet manifest")
    if type(manifest["schema_version"]) is not int or manifest["schema_version"] != 1:
        reject("historical audited packet schema_version is invalid")
    if (manifest["attempt_id"] != attempt_id or manifest["review_mode"] != "verification" or
            manifest["audit_version"] != version):
        reject("historical audited packet attempt/review/version binding is invalid")
    safe_id(manifest["output_id"], "historical audited packet output_id")
    bounded_text(manifest["review_question"], 2000, "historical audited packet review_question")
    expected_corrected = "audit/versions/%s/corrected-audit.md" % version
    if manifest["corrected_audit_path"] != expected_corrected:
        reject("historical audited packet corrected path is invalid")
    expected_denied = [
        "run-log", "run-state-and-delegate-state", "checkpoint-log-slices",
        "prior-challenger-or-notary-findings-and-verdicts", "conductor-or-author-rationale",
        "visionary-back-and-forth", "chat-and-session-transcripts", "files-absent-from-allowlist",
    ]
    if manifest["denied_inputs"] != expected_denied:
        reject("historical audited packet denied_inputs is invalid")
    if not isinstance(manifest["allowlist"], list) or not manifest["allowlist"]:
        reject("historical audited packet allowlist is invalid")
    historical_entries = []
    historical_raw_paths = []
    historical_lower = set()
    for index, item in enumerate(manifest["allowlist"]):
        exact_keys(item, ["path", "sha256"], "historical allowlist[%d]" % index)
        raw_path = safe_packet_path(item["path"], "historical allowlist path")
        if not isinstance(item["sha256"], str) or SHA256.fullmatch(item["sha256"]) is None:
            reject("historical allowlist hash is invalid")
        if raw_path in historical_raw_paths or raw_path.lower() in historical_lower:
            reject("historical allowlist contains a duplicate or case-colliding path")
        historical_raw_paths.append(raw_path)
        historical_lower.add(raw_path.lower())
        historical_entries.append((item["path"], item["sha256"]))
    if historical_raw_paths != sorted(historical_raw_paths):
        reject("historical allowlist is not canonically sorted")
    historical_map = dict(historical_entries)
    if manifest["allowlist"] != verdict["reviewed_artifacts"]:
        reject("historical audited verdict read set differs from immutable packet allowlist")
    if historical_map.get(expected_corrected) != corrected_hash:
        reject("historical audited packet corrected version/hash binding is invalid")
    if (seal["contract_sha256"] != historical_map.get("audit/product-contract.md") or
            seal["shared_contract_path"] != "docs/codebase-readiness-audit-contract.md" or
            seal["shared_contract_sha256"] != historical_map.get(seal["shared_contract_path"])):
        reject("historical audited seal contract hashes do not bind packet-era immutable members")

    actual = []
    identities = {}
    directory_identities = {}
    for current, directories, files in os.walk(historical_root, topdown=True, followlinks=False):
        current_info = os.lstat(current)
        if stat.S_ISLNK(current_info.st_mode) or not stat.S_ISDIR(current_info.st_mode):
            reject("historical packet contains a symlink or special directory")
        current_identity = (current_info.st_dev, current_info.st_ino)
        if current_identity in directory_identities:
            reject("historical packet contains a directory identity alias")
        directory_identities[current_identity] = current
        for name in directories:
            member = os.path.join(current, name)
            member_mode = os.lstat(member).st_mode
            if stat.S_ISLNK(member_mode) or not stat.S_ISDIR(member_mode):
                reject("historical packet contains a symlink or special directory")
        for name in files:
            member = os.path.join(current, name)
            info = os.lstat(member)
            if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
                reject("historical packet contains a symlink or special file")
            relative = os.path.relpath(member, historical_root)
            safe_packet_path(relative, "historical staged file path")
            actual.append(relative)
            identity = (info.st_dev, info.st_ino)
            if identity in identities or info.st_nlink != 1:
                reject("historical packet contains a hard-link or identity alias")
            identities[identity] = relative
    for identity, directory in directory_identities.items():
        current_info = os.lstat(directory)
        if stat.S_ISLNK(current_info.st_mode) or (current_info.st_dev, current_info.st_ino) != identity:
            reject("historical packet directory identity changed during enumeration")
    if set(actual) != {"packet.json"} | set(historical_map):
        reject("historical packet file set does not equal packet.json plus allowlist")
    for relative, expected_hash in historical_entries:
        if sha_file(ensure_plain_path(historical_root, relative)) != expected_hash:
            reject("historical staged payload hash mismatch: " + relative)

    result_name = attempt_id + "-result"
    result_matches = [name for name in os.listdir(reviews_parent) if name.lower() == result_name.lower()]
    if result_matches != [result_name]:
        reject("historical audited result directory is missing, non-unique, or case-colliding")
    result_root = os.path.join(reviews_parent, result_name)
    result_mode = os.lstat(result_root).st_mode
    if stat.S_ISLNK(result_mode) or not stat.S_ISDIR(result_mode):
        reject("historical audited result root is a symlink or not a directory")
    expected_result_name = manifest["output_id"] + ".json"
    result_members = os.listdir(result_root)
    if result_members != [expected_result_name]:
        reject("historical audited result does not contain exactly the bound output member")
    result_path = os.path.join(result_root, expected_result_name)
    result_info = os.lstat(result_path)
    if (stat.S_ISLNK(result_info.st_mode) or not stat.S_ISREG(result_info.st_mode) or
            result_info.st_nlink != 1):
        reject("historical audited result member is a symlink or not a regular file")
    candidate, candidate_raw = load_json_bytes(result_path)
    exact_keys(candidate, ["attempt_id", "review_mode", "reviewed_artifacts", "blocker_ids",
                           "blockers", "warnings"], "historical audited result candidate")
    expected_candidate = {key: value for key, value in verdict.items() if key not in {"verdict", "timestamp"}}
    if candidate != expected_candidate:
        reject("historical audited result candidate differs from canonical verdict content")
    try:
        candidate_text = candidate_raw.decode("utf-8")
        candidate_decoder = json.JSONDecoder(object_pairs_hook=pairs_object)
        candidate_start = 0
        while candidate_start < len(candidate_text) and candidate_text[candidate_start] in " \t\r\n":
            candidate_start += 1
        unused_candidate, candidate_end = candidate_decoder.raw_decode(candidate_text, candidate_start)
    except (UnicodeDecodeError, ValueError, json.JSONDecodeError) as exc:
        reject("historical audited result raw bytes are invalid: %s" % exc)
    if candidate_end <= candidate_start or candidate_text[candidate_end - 1] != "}":
        reject("historical audited result raw bytes do not end in one object")
    expected_verdict_raw = (
        candidate_text[:candidate_end - 1] +
        ',"verdict":' + json.dumps(verdict["verdict"], ensure_ascii=True, separators=(",", ":")) +
        ',"timestamp":' + json.dumps(verdict["timestamp"], ensure_ascii=True, separators=(",", ":")) +
        '}' + candidate_text[candidate_end:]
    ).encode("utf-8")
    if verdict_raw != expected_verdict_raw:
        reject("historical audited result raw bytes do not bind the canonical verdict bytes")

    historical_reservation_relative = "audit/versions/%s/reservation.json" % version
    historical_reservation, unused = load_json_bytes(
        ensure_plain_path(historical_root, historical_reservation_relative))
    exact_keys(historical_reservation, ["schema_version", "audit_version", "allocation_id",
                                       "reconciliation_attempt_id", "reserved_at"],
               "historical audited reservation")
    if type(historical_reservation["schema_version"]) is not int or historical_reservation["schema_version"] != 1:
        reject("historical audited reservation schema_version is invalid")
    if historical_reservation["audit_version"] != version:
        reject("historical audited reservation version binding is invalid")
    safe_id(historical_reservation["allocation_id"], "historical audited reservation allocation_id")
    safe_id(historical_reservation["reconciliation_attempt_id"],
            "historical audited reservation reconciliation_attempt_id")
    valid_timestamp(historical_reservation["reserved_at"], "historical audited reservation reserved_at")
    if historical_reservation != validate_authoritative_reservation(version):
        reject("historical audited reservation differs from authoritative immutable reservation")

    historical_coverage = validate_coverage_semantics(historical_root, historical_map)
    historical_index_path = ensure_plain_path(historical_root, "audit/version-index.ndjson")
    historical_index_raw = read_plain_bytes(historical_index_path)
    historical_events = load_strict_version_index(historical_index_path)
    historical_versions = {}
    historical_last_number = 0
    historical_last_event = None
    selected_events = []
    for event in historical_events:
        kind = event.get("event")
        if kind == "corrected":
            exact_keys(event, ["schema_version", "audit_version", "event", "artifact_path",
                               "artifact_sha256", "recorded_at"], "historical corrected index event")
        elif kind == "sealed":
            exact_keys(event, ["schema_version", "audit_version", "event", "corrected_audit_path",
                               "corrected_audit_sha256", "recorded_at", "seal_path", "seal_sha256"],
                       "historical sealed index event")
        else:
            reject("historical version index contains an unknown event")
        if type(event["schema_version"]) is not int or event["schema_version"] != 1:
            reject("historical version index schema_version is invalid")
        event_version = event["audit_version"]
        if not isinstance(event_version, str) or AUDIT_VERSION.fullmatch(event_version) is None:
            reject("historical version index audit_version is invalid")
        number = int(event_version[1:])
        valid_timestamp(event["recorded_at"], "historical version index recorded_at")
        corrected_relative = "audit/versions/%s/corrected-audit.md" % event_version
        if kind == "corrected":
            if number <= historical_last_number or event_version in historical_versions:
                reject("historical version index corrected order is impossible")
            if (event["artifact_path"] != corrected_relative or
                    not isinstance(event["artifact_sha256"], str) or SHA256.fullmatch(event["artifact_sha256"]) is None):
                reject("historical corrected index path/hash is invalid")
            historical_versions[event_version] = event["artifact_sha256"]
            if event_version == version:
                selected_events.append(event)
        else:
            if (event_version not in historical_versions or number != historical_last_number or
                    historical_last_event != (event_version, "corrected")):
                reject("historical version index sealed order is impossible")
            if (event["corrected_audit_path"] != corrected_relative or
                    event["corrected_audit_sha256"] != historical_versions[event_version] or
                    event["seal_path"] != "audit/versions/%s/seal.json" % event_version or
                    not isinstance(event["seal_sha256"], str) or SHA256.fullmatch(event["seal_sha256"]) is None):
                reject("historical sealed index binding is invalid")
        historical_last_number = number
        historical_last_event = (event_version, kind)
    if len(selected_events) != 1:
        reject("historical version index lacks exactly one selected corrected event")
    selected_event = selected_events[0]
    if (selected_event["artifact_path"] != expected_corrected or
            selected_event["artifact_sha256"] != corrected_hash or
            historical_map.get(expected_corrected) != corrected_hash):
        reject("historical selected version-index binding is invalid")
    authoritative_selected = [index for index, event in enumerate(version_events)
                              if event.get("event") == "corrected" and
                              event.get("audit_version") == version]
    if len(authoritative_selected) != 1:
        reject("authoritative history lacks exactly one historical corrected event")
    selected_position = authoritative_selected[0]
    authoritative_prefix = version_events[:selected_position + 1]
    if historical_events != authoritative_prefix:
        reject("historical packet-era version index differs from authoritative history")
    authoritative_index_raw = read_plain_bytes(version_index_source)
    authoritative_lines = authoritative_index_raw.splitlines(keepends=True)
    if (len(authoritative_lines) != len(version_events) or
            historical_index_raw != b"".join(authoritative_lines[:selected_position + 1])):
        reject("historical packet-era version-index bytes differ from authoritative append-only history")
    authoritative_version = indexed_versions.get(version)
    if authoritative_version is None:
        reject("historical audited version is absent from authoritative index state")
    following_event = (version_events[selected_position + 1]
                       if selected_position + 1 < len(version_events) else None)
    if authoritative_version["sealed"]:
        seal_relative = "audit/versions/%s/seal.json" % version
        seal_hash = sha_file(ensure_plain_path(run_dir, seal_relative))
        if (not isinstance(following_event, dict) or
                following_event.get("event") != "sealed" or
                following_event.get("audit_version") != version or
                following_event.get("corrected_audit_path") != expected_corrected or
                following_event.get("corrected_audit_sha256") != corrected_hash or
                following_event.get("seal_path") != seal_relative or
                following_event.get("seal_sha256") != seal_hash):
            reject("historical audited sealed event does not bind the authoritative seal lineage")
    elif following_event is not None and (following_event.get("event") == "sealed" and
                                           following_event.get("audit_version") == version):
        reject("historical audited seal/index state is internally inconsistent")
    required = {
        "audit/profile.md", "audit/product-contract.md", "audit/domain-register.md",
        "audit/coverage-index.ndjson", "audit/runtime-verification.md", "audit/setup-quarantine.md",
        "audit/versions/%s/reservation.json" % version, "audit/version-index.ndjson", expected_corrected,
        "docs/codebase-readiness-audit-contract.md", "workflows/codebase-readiness-audit.md",
        "agents/critic/readiness-audit.md",
    } | set(historical_coverage)
    if set(historical_map) != required:
        reject("historical audited packet allowlist is not the exact contract member set")

def validate_recoverable_or_indexed_seal(version, corrected_hash):
    relative = "audit/versions/%s/seal.json" % version
    value, unused = load_json_bytes(ensure_plain_path(run_dir, relative))
    base_keys = {"schema_version", "audit_version", "profile", "target_commit", "audit_date",
                 "corrected_audit_path", "corrected_audit_sha256", "contract_sha256",
                 "shared_contract_path", "shared_contract_sha256", "completeness", "conclusiveness",
                 "successful_run", "selectable_for_remediation_planning", "selection_reason",
                 "sealing_path", "cold_review"}
    audited_keys = {"cold_review_verdict", "cold_review_verdict_path", "cold_review_verdict_sha256"}
    if not isinstance(value, dict) or value.get("profile") not in {"catalog", "full", "audited"}:
        reject("seal profile is missing or invalid")
    expected_keys = base_keys | audited_keys if value["profile"] == "audited" else base_keys
    if set(value) != expected_keys:
        reject("seal has the wrong profile-conditional exact key set")
    if type(value["schema_version"]) is not int or value["schema_version"] != 1:
        reject("seal schema_version is invalid")
    if value["audit_version"] != version:
        reject("seal audit_version binding is invalid")
    if not isinstance(value["target_commit"], str) or re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", value["target_commit"]) is None:
        reject("seal target_commit is invalid")
    if not isinstance(value["audit_date"], str) or DATE.fullmatch(value["audit_date"]) is None:
        reject("seal audit_date is invalid")
    try:
        datetime.datetime.strptime(value["audit_date"], "%Y-%m-%d")
    except ValueError:
        reject("seal audit_date is not a real date")
    corrected_relative = "audit/versions/%s/corrected-audit.md" % version
    if (value["corrected_audit_path"] != corrected_relative or
            value["corrected_audit_sha256"] != corrected_hash):
        reject("seal corrected-audit binding is invalid")
    for key in ["contract_sha256", "shared_contract_sha256"]:
        if not isinstance(value[key], str) or SHA256.fullmatch(value[key]) is None:
            reject("seal %s is invalid" % key)
    if value["shared_contract_path"] != "docs/codebase-readiness-audit-contract.md":
        reject("seal shared-contract path is invalid")
    matrix = {
        ("incomplete", "non-conclusive"): (False, False, "incomplete-evidence-only"),
        ("complete", "non-conclusive"): (True, True, "complete-evidence-limited"),
        ("complete", "conclusive"): (True, True, "complete-conclusive"),
    }
    matrix_value = matrix.get((value["completeness"], value["conclusiveness"]))
    if (matrix_value is None or type(value["successful_run"]) is not bool or
            type(value["selectable_for_remediation_planning"]) is not bool or
            (value["successful_run"], value["selectable_for_remediation_planning"],
             value["selection_reason"]) != matrix_value):
        reject("seal completeness/conclusiveness matrix binding is invalid")
    if value["profile"] in {"catalog", "full"}:
        if value["sealing_path"] != "standard-non-premium" or value["cold_review"] != "not-performed":
            reject("standard-profile seal path is invalid")
    else:
        if (value["sealing_path"] != "premium-independent-cold-review" or
                value["cold_review"] != "performed" or
                value["cold_review_verdict"] not in {"APPROVED_WITH_WARNINGS", "APPROVED"}):
            reject("audited seal cold-review state is invalid")
        verdict_path = value["cold_review_verdict_path"]
        if not isinstance(verdict_path, str) or re.fullmatch(r"verdicts/([a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?)\.json", verdict_path) is None:
            reject("audited seal verdict path is invalid")
        if not isinstance(value["cold_review_verdict_sha256"], str) or SHA256.fullmatch(value["cold_review_verdict_sha256"]) is None:
            reject("audited seal verdict hash is invalid")
        if sha_file(ensure_plain_path(run_dir, verdict_path)) != value["cold_review_verdict_sha256"]:
            reject("audited seal verdict file/hash mismatch")
        validate_historical_audited_review(version, corrected_hash, value)

def validate_existing_readiness_verdict(verdict_relative):
    match = re.fullmatch(r"verdicts/([a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?)\.json", verdict_relative)
    value, verdict_raw = load_json_bytes(ensure_plain_path(run_dir, verdict_relative))
    if not isinstance(value, dict):
        reject("existing canonical verdict is not an object: " + verdict_relative)
    if value.get("review_mode") != "verification":
        return None
    if match is None:
        reject("existing readiness verdict path has an invalid attempt basename")
    attempt = match.group(1)
    exact_keys(value, ["attempt_id", "review_mode", "reviewed_artifacts", "blocker_ids",
                       "blockers", "warnings", "verdict", "timestamp"], "existing readiness verdict")
    if value["attempt_id"] != attempt:
        reject("existing readiness verdict attempt/path binding is invalid")
    valid_timestamp(value["timestamp"], "existing readiness verdict timestamp")
    if not isinstance(value["blocker_ids"], list) or not isinstance(value["blockers"], list) or not isinstance(value["warnings"], list):
        reject("existing readiness verdict arrays are invalid")
    ids = []
    all_ids = set()
    allowed = set()
    if not isinstance(value["reviewed_artifacts"], list) or not value["reviewed_artifacts"]:
        reject("existing readiness verdict reviewed_artifacts is invalid")
    raw_paths = []
    for index, item in enumerate(value["reviewed_artifacts"]):
        exact_keys(item, ["path", "sha256"], "existing readiness reviewed_artifacts[%d]" % index)
        raw_path = safe_packet_path(item["path"], "existing readiness reviewed path")
        if not isinstance(item["sha256"], str) or SHA256.fullmatch(item["sha256"]) is None or item["path"] in allowed:
            reject("existing readiness reviewed artifact path/hash is invalid")
        allowed.add(item["path"])
        raw_paths.append(raw_path)
    if raw_paths != sorted(raw_paths):
        reject("existing readiness reviewed_artifacts is not canonically sorted")
    for blocker in value["blockers"]:
        exact_keys(blocker, ["id", "summary", "citation"], "existing readiness blocker")
        safe_id(blocker["id"], "existing readiness blocker id")
        bounded_text(blocker["summary"], 1000, "existing readiness blocker summary")
        if blocker["id"] in all_ids:
            reject("existing readiness verdict contains colliding IDs")
        all_ids.add(blocker["id"]); ids.append(blocker["id"])
        citation = blocker["citation"]
        if not isinstance(citation, dict) or citation.get("kind") not in {"presence", "absence"}:
            reject("existing readiness blocker citation is invalid")
        citation_keys = ["kind", "path", "anchor"] if citation["kind"] == "presence" else ["kind", "path", "missing"]
        exact_keys(citation, citation_keys, "existing readiness blocker citation")
        bounded_text(citation[citation_keys[-1]], 1000, "existing readiness citation text")
        if citation["path"] not in allowed:
            reject("existing readiness citation path is outside reviewed_artifacts")
    if value["blocker_ids"] != ids:
        reject("existing readiness blocker_ids is not derived from blockers")
    for warning in value["warnings"]:
        exact_keys(warning, ["id", "summary"], "existing readiness warning")
        safe_id(warning["id"], "existing readiness warning id")
        bounded_text(warning["summary"], 1000, "existing readiness warning summary")
        if warning["id"] in all_ids:
            reject("existing readiness verdict contains colliding IDs")
        all_ids.add(warning["id"])
    derived = "BLOCKED" if ids else "APPROVED_WITH_WARNINGS" if value["warnings"] else "APPROVED"
    if value["verdict"] != derived:
        reject("existing readiness verdict is not mechanically derived")

    reviews_parent = os.path.join(run_dir, "audit", "reviews")
    packet_name = attempt + "-packet"
    matches = [name for name in os.listdir(reviews_parent) if name.lower() == packet_name.lower()]
    if matches != [packet_name]:
        reject("existing readiness verdict lacks one unique immutable packet")
    existing_root = os.path.join(reviews_parent, packet_name)
    existing_root_mode = os.lstat(existing_root).st_mode
    if stat.S_ISLNK(existing_root_mode) or not stat.S_ISDIR(existing_root_mode):
        reject("existing readiness packet root is a symlink or not a directory")
    manifest, unused = load_json_bytes(ensure_plain_path(existing_root, "packet.json"))
    exact_keys(manifest, ["schema_version", "audit_version", "corrected_audit_path", "review_question",
                          "attempt_id", "output_id", "review_mode", "denied_inputs", "allowlist"],
               "existing readiness packet")
    if (type(manifest["schema_version"]) is not int or manifest["schema_version"] != 1 or
            not isinstance(manifest["audit_version"], str) or AUDIT_VERSION.fullmatch(manifest["audit_version"]) is None or
            manifest["attempt_id"] != attempt or manifest["review_mode"] != "verification" or
            manifest["allowlist"] != value["reviewed_artifacts"]):
        reject("existing readiness packet binding is invalid")
    safe_id(manifest["output_id"], "existing readiness output_id")
    bounded_text(manifest["review_question"], 2000, "existing readiness review_question")
    expected_denied = [
        "run-log", "run-state-and-delegate-state", "checkpoint-log-slices",
        "prior-challenger-or-notary-findings-and-verdicts", "conductor-or-author-rationale",
        "visionary-back-and-forth", "chat-and-session-transcripts", "files-absent-from-allowlist",
    ]
    if manifest["denied_inputs"] != expected_denied:
        reject("existing readiness packet denied_inputs is invalid")
    version = manifest["audit_version"]
    corrected_relative = "audit/versions/%s/corrected-audit.md" % version
    if manifest["corrected_audit_path"] != corrected_relative:
        reject("existing readiness packet corrected path is invalid")
    safe_packet_path(manifest["corrected_audit_path"], "existing readiness corrected path")

    existing_entries = []
    existing_paths = []
    existing_lower = set()
    for index, item in enumerate(manifest["allowlist"]):
        exact_keys(item, ["path", "sha256"], "existing readiness allowlist[%d]" % index)
        raw_path = safe_packet_path(item["path"], "existing readiness allowlist path")
        if not isinstance(item["sha256"], str) or SHA256.fullmatch(item["sha256"]) is None:
            reject("existing readiness allowlist hash is invalid")
        if raw_path in existing_paths or raw_path.lower() in existing_lower:
            reject("existing readiness allowlist contains a duplicate or case-colliding path")
        existing_paths.append(raw_path)
        existing_lower.add(raw_path.lower())
        existing_entries.append((item["path"], item["sha256"]))
    if existing_paths != sorted(existing_paths):
        reject("existing readiness allowlist is not canonically sorted")
    existing_map = dict(existing_entries)

    actual = []
    identities = {}
    directory_identities = {}
    for current, directories, files in os.walk(existing_root, topdown=True, followlinks=False):
        current_info = os.lstat(current)
        if stat.S_ISLNK(current_info.st_mode) or not stat.S_ISDIR(current_info.st_mode):
            reject("existing readiness packet contains a symlink or special directory")
        current_identity = (current_info.st_dev, current_info.st_ino)
        if current_identity in directory_identities:
            reject("existing readiness packet contains a directory identity alias")
        directory_identities[current_identity] = current
        for name in directories:
            member = os.path.join(current, name)
            member_mode = os.lstat(member).st_mode
            if stat.S_ISLNK(member_mode) or not stat.S_ISDIR(member_mode):
                reject("existing readiness packet contains a symlink or special directory")
        for name in files:
            member = os.path.join(current, name)
            info = os.lstat(member)
            if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
                reject("existing readiness packet contains a symlink or special file")
            relative = os.path.relpath(member, existing_root)
            safe_packet_path(relative, "existing readiness staged file path")
            actual.append(relative)
            identity = (info.st_dev, info.st_ino)
            if identity in identities or info.st_nlink != 1:
                reject("existing readiness packet contains a hard-link or identity alias")
            identities[identity] = relative
    for identity, directory in directory_identities.items():
        current_info = os.lstat(directory)
        if stat.S_ISLNK(current_info.st_mode) or (current_info.st_dev, current_info.st_ino) != identity:
            reject("existing readiness packet directory identity changed during enumeration")
    if set(actual) != {"packet.json"} | set(existing_map):
        reject("existing readiness packet file set does not equal packet.json plus allowlist")
    for relative, expected_hash in existing_entries:
        if sha_file(ensure_plain_path(existing_root, relative)) != expected_hash:
            reject("existing readiness packet payload hash mismatch: " + relative)

    coverage_paths = validate_coverage_semantics(existing_root, existing_map)
    reservation_relative = "audit/versions/%s/reservation.json" % version
    required = {
        "audit/profile.md", "audit/product-contract.md", "audit/domain-register.md",
        "audit/coverage-index.ndjson", "audit/runtime-verification.md", "audit/setup-quarantine.md",
        reservation_relative, "audit/version-index.ndjson", corrected_relative,
        "docs/codebase-readiness-audit-contract.md", "workflows/codebase-readiness-audit.md",
        "agents/critic/readiness-audit.md",
    } | set(coverage_paths)
    if set(existing_map) != required:
        reject("existing readiness packet allowlist is not the exact contract member set")

    staged_reservation, unused = load_json_bytes(ensure_plain_path(existing_root, reservation_relative))
    exact_keys(staged_reservation, ["schema_version", "audit_version", "allocation_id",
                                    "reconciliation_attempt_id", "reserved_at"],
               "existing readiness reservation")
    if type(staged_reservation["schema_version"]) is not int or staged_reservation["schema_version"] != 1:
        reject("existing readiness reservation schema_version is invalid")
    if staged_reservation["audit_version"] != version:
        reject("existing readiness reservation version binding is invalid")
    safe_id(staged_reservation["allocation_id"], "existing readiness reservation allocation_id")
    safe_id(staged_reservation["reconciliation_attempt_id"],
            "existing readiness reservation reconciliation_attempt_id")
    valid_timestamp(staged_reservation["reserved_at"], "existing readiness reservation reserved_at")
    if staged_reservation != validate_authoritative_reservation(version):
        reject("existing readiness reservation differs from authoritative immutable reservation")

    staged_events = load_strict_version_index(
        ensure_plain_path(existing_root, "audit/version-index.ndjson"))
    staged_versions = {}
    staged_last_number = 0
    staged_last_event = None
    selected = []
    for event in staged_events:
        kind = event.get("event")
        if kind == "corrected":
            exact_keys(event, ["schema_version", "audit_version", "event", "artifact_path",
                               "artifact_sha256", "recorded_at"],
                       "existing readiness corrected index event")
        elif kind == "sealed":
            exact_keys(event, ["schema_version", "audit_version", "event", "corrected_audit_path",
                               "corrected_audit_sha256", "recorded_at", "seal_path", "seal_sha256"],
                       "existing readiness sealed index event")
        else:
            reject("existing readiness version index contains an unknown event")
        if type(event["schema_version"]) is not int or event["schema_version"] != 1:
            reject("existing readiness version index schema_version is invalid")
        event_version = event["audit_version"]
        if not isinstance(event_version, str) or AUDIT_VERSION.fullmatch(event_version) is None:
            reject("existing readiness version index audit_version is invalid")
        number = int(event_version[1:])
        valid_timestamp(event["recorded_at"], "existing readiness version index recorded_at")
        event_corrected = "audit/versions/%s/corrected-audit.md" % event_version
        if kind == "corrected":
            if number <= staged_last_number or event_version in staged_versions:
                reject("existing readiness version index corrected order is impossible")
            if (event["artifact_path"] != event_corrected or
                    not isinstance(event["artifact_sha256"], str) or
                    SHA256.fullmatch(event["artifact_sha256"]) is None):
                reject("existing readiness corrected index path/hash is invalid")
            staged_versions[event_version] = event["artifact_sha256"]
            if event_version == version:
                selected.append(event)
        else:
            if (event_version not in staged_versions or number != staged_last_number or
                    staged_last_event != (event_version, "corrected")):
                reject("existing readiness version index sealed order is impossible")
            if (event["corrected_audit_path"] != event_corrected or
                    event["corrected_audit_sha256"] != staged_versions[event_version] or
                    event["seal_path"] != "audit/versions/%s/seal.json" % event_version or
                    not isinstance(event["seal_sha256"], str) or SHA256.fullmatch(event["seal_sha256"]) is None):
                reject("existing readiness sealed index binding is invalid")
        staged_last_number = number
        staged_last_event = (event_version, kind)
    if len(selected) != 1:
        reject("existing readiness version index lacks exactly one selected corrected event")
    selected_event = selected[0]
    authority_events = [event for event in version_events
                        if event.get("event") == "corrected" and event.get("audit_version") == version]
    if len(authority_events) != 1:
        reject("existing readiness version lacks one authoritative corrected event")
    authority_event = authority_events[0]
    if (selected_event["artifact_path"] != corrected_relative or
            selected_event["artifact_sha256"] != existing_map.get(corrected_relative) or
            authority_event["artifact_path"] != corrected_relative or
            authority_event["artifact_sha256"] != selected_event["artifact_sha256"] or
            sha_file(ensure_plain_path(run_dir, corrected_relative)) != selected_event["artifact_sha256"]):
        reject("existing readiness corrected/index authority binding is invalid")

    result_root = os.path.join(reviews_parent, attempt + "-result")
    result_matches = [name for name in os.listdir(reviews_parent) if name.lower() == (attempt + "-result").lower()]
    if result_matches != [attempt + "-result"]:
        reject("existing readiness result directory is missing or aliased")
    result_mode = os.lstat(result_root).st_mode
    if stat.S_ISLNK(result_mode) or not stat.S_ISDIR(result_mode):
        reject("existing readiness result directory is a symlink or not a directory")
    expected_name = manifest["output_id"] + ".json"
    if os.listdir(result_root) != [expected_name]:
        reject("existing readiness result member set is invalid")
    result_path = os.path.join(result_root, expected_name)
    info = os.lstat(result_path)
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
        reject("existing readiness result member is not a regular no-alias file")
    candidate, candidate_raw = load_json_bytes(result_path)
    exact_keys(candidate, ["attempt_id", "review_mode", "reviewed_artifacts", "blocker_ids",
                           "blockers", "warnings"], "existing readiness result candidate")
    if candidate != {key: item for key, item in value.items() if key not in {"verdict", "timestamp"}}:
        reject("existing readiness result candidate differs from canonical verdict")
    try:
        candidate_text = candidate_raw.decode("utf-8")
        candidate_decoder = json.JSONDecoder(object_pairs_hook=pairs_object)
        candidate_start = 0
        while candidate_start < len(candidate_text) and candidate_text[candidate_start] in " \t\r\n":
            candidate_start += 1
        unused_candidate, candidate_end = candidate_decoder.raw_decode(candidate_text, candidate_start)
    except (UnicodeDecodeError, ValueError, json.JSONDecodeError) as exc:
        reject("existing readiness result raw bytes are invalid: %s" % exc)
    if candidate_end <= candidate_start or candidate_text[candidate_end - 1] != "}":
        reject("existing readiness result raw bytes do not end in one object")
    expected_verdict_raw = (
        candidate_text[:candidate_end - 1] +
        ',"verdict":' + json.dumps(value["verdict"], ensure_ascii=True, separators=(",", ":")) +
        ',"timestamp":' + json.dumps(value["timestamp"], ensure_ascii=True, separators=(",", ":")) +
        '}' + candidate_text[candidate_end:]
    ).encode("utf-8")
    if verdict_raw != expected_verdict_raw:
        reject("existing readiness result raw bytes do not bind the canonical verdict bytes")
    return manifest["audit_version"], value["verdict"]

version_index_source = ensure_plain_path(run_dir, "audit/version-index.ndjson")
version_events = load_strict_version_index(version_index_source)
matching = []
event_identity = set()
indexed_versions = {}
last_version_number = 0
last_event = None
for event in version_events:
    kind = event.get("event")
    if kind == "corrected":
        exact_keys(event, ["schema_version", "audit_version", "event", "artifact_path",
                           "artifact_sha256", "recorded_at"], "corrected index event")
    elif kind == "sealed":
        exact_keys(event, ["schema_version", "audit_version", "event", "corrected_audit_path",
                           "corrected_audit_sha256", "recorded_at", "seal_path", "seal_sha256"],
                   "sealed index event")
    else:
        reject("version index contains an unknown event")
    if type(event["schema_version"]) is not int or event["schema_version"] != 1:
        reject("version index event schema_version is invalid")
    version = event["audit_version"]
    if not isinstance(version, str) or AUDIT_VERSION.fullmatch(version) is None:
        reject("version index event audit_version is invalid")
    version_number = int(version[1:])
    if version_number < last_version_number:
        reject("version index audit versions decrease")
    identity = (version, kind)
    if identity in event_identity:
        reject("version index contains a duplicate or conflicting event identity")
    event_identity.add(identity)
    valid_timestamp(event["recorded_at"], "version index recorded_at")
    validate_authoritative_reservation(version)

    corrected_relative = "audit/versions/%s/corrected-audit.md" % version
    if kind == "corrected":
        if version_number <= last_version_number or version in indexed_versions:
            reject("version index corrected event order is impossible")
        if event["artifact_path"] != corrected_relative:
            reject("corrected index event artifact path is invalid")
        if not isinstance(event["artifact_sha256"], str) or SHA256.fullmatch(event["artifact_sha256"]) is None:
            reject("corrected index event artifact hash is invalid")
        corrected_source = ensure_plain_path(run_dir, corrected_relative)
        if sha_file(corrected_source) != event["artifact_sha256"]:
            reject("corrected index event artifact file/hash mismatch")
        indexed_versions[version] = {"corrected_sha256": event["artifact_sha256"], "sealed": False}
        if version == audit_version:
            matching.append(event)
    else:
        if (version not in indexed_versions or version_number != last_version_number or
                last_event != (version, "corrected")):
            reject("version index contains sealed-before-corrected or impossible event order")
        if event["corrected_audit_path"] != corrected_relative:
            reject("sealed index event corrected-audit path is invalid")
        if event["corrected_audit_sha256"] != indexed_versions[version]["corrected_sha256"]:
            reject("sealed index event corrected-audit hash conflicts with corrected event")
        corrected_source = ensure_plain_path(run_dir, corrected_relative)
        if sha_file(corrected_source) != event["corrected_audit_sha256"]:
            reject("sealed index event corrected-audit file/hash mismatch")
        seal_relative = "audit/versions/%s/seal.json" % version
        if event["seal_path"] != seal_relative:
            reject("sealed index event seal path is invalid")
        if not isinstance(event["seal_sha256"], str) or SHA256.fullmatch(event["seal_sha256"]) is None:
            reject("sealed index event seal hash is invalid")
        seal_source = ensure_plain_path(run_dir, seal_relative)
        if sha_file(seal_source) != event["seal_sha256"]:
            reject("sealed index event seal file/hash mismatch")
        indexed_versions[version]["sealed"] = True
    last_version_number = version_number
    last_event = identity

versions_root = os.path.join(run_dir, "audit", "versions")
try:
    versions_info = os.lstat(versions_root)
except OSError as exc:
    reject("authoritative versions directory is missing: %s" % exc)
if stat.S_ISLNK(versions_info.st_mode) or not stat.S_ISDIR(versions_info.st_mode):
    reject("authoritative versions path is not a regular directory")
versions_identity = (versions_info.st_dev, versions_info.st_ino)
version_names = os.listdir(versions_root)
for version in version_names:
    if AUDIT_VERSION.fullmatch(version) is None:
        reject("versions directory contains an invalid version name")
highest_existing_number = max((int(version[1:]) for version in version_names), default=0)
version_directory_identities = {}
version_members = {}
for version in version_names:
    if AUDIT_VERSION.fullmatch(version) is None:
        reject("versions directory contains an invalid version name")
    version_dir = os.path.join(versions_root, version)
    version_info = os.lstat(version_dir)
    if stat.S_ISLNK(version_info.st_mode) or not stat.S_ISDIR(version_info.st_mode):
        reject("version path is a symlink or not a directory: " + version)
    version_identity = (version_info.st_dev, version_info.st_ino)
    if version_identity in version_directory_identities:
        reject("version directory contains an identity alias")
    version_directory_identities[version_identity] = version_dir
    validate_authoritative_reservation(version)
    names = set(os.listdir(version_dir))
    version_members[version] = names
    for name in names:
        member = os.path.join(version_dir, name)
        member_info = os.lstat(member)
        if (stat.S_ISLNK(member_info.st_mode) or not stat.S_ISREG(member_info.st_mode) or
                member_info.st_nlink != 1):
            reject("version directory contains a symlink or special member: %s/%s" % (version, name))
    indexed = indexed_versions.get(version)
    version_number = int(version[1:])
    if indexed is None:
        if names not in ({"reservation.json"}, {"reservation.json", "corrected-audit.md"}):
            reject("unindexed version directory is not reserved-only or recoverable corrected state")
        if version_number <= last_version_number:
            reject("unindexed version directory cannot legally follow the version index")
        if "corrected-audit.md" in names and version_number != highest_existing_number:
            reject("older unindexed corrected-audit state is not recoverable")
    elif indexed["sealed"]:
        if names != {"reservation.json", "corrected-audit.md", "seal.json"}:
            reject("sealed version directory has an invalid artifact set")
    elif names not in ({"reservation.json", "corrected-audit.md"},
                        {"reservation.json", "corrected-audit.md", "seal.json"}):
        reject("corrected version directory has an invalid artifact set")
    elif "seal.json" in names and (version_number != highest_existing_number or
                                    last_event != (version, "corrected")):
        reject("older or nonterminal unindexed seal state is not recoverable")
    if "seal.json" in names:
        corrected_hash = (indexed["corrected_sha256"] if indexed is not None else
                          sha_file(ensure_plain_path(run_dir, "audit/versions/%s/corrected-audit.md" % version)))
        validate_recoverable_or_indexed_seal(version, corrected_hash)
for identity, directory in version_directory_identities.items():
    current_info = os.lstat(directory)
    if stat.S_ISLNK(current_info.st_mode) or (current_info.st_dev, current_info.st_ino) != identity:
        reject("version directory identity changed during validation")
current_versions_info = os.lstat(versions_root)
if (current_versions_info.st_dev, current_versions_info.st_ino) != versions_identity:
    reject("authoritative versions directory identity changed during validation")
for version in indexed_versions:
    if version not in version_names:
        reject("version index names a missing version directory")

if len(matching) != 1:
    reject("version index lacks exactly one corrected event for audit_version")
corrected_event = matching[0]
if (corrected_event["artifact_path"] != expected_corrected or
        corrected_event["artifact_sha256"] != entry_map[expected_corrected]):
    reject("selected corrected index event path/hash binding is invalid")
if "seal.json" in version_members.get(audit_version, set()):
    reject("selected audit_version is already sealed")

# A canonical BLOCKED verdict retires its corrected version. A fresh transport
# attempt may reuse unchanged bytes only while no canonical verdict exists.
verdicts_root = os.path.join(run_dir, "verdicts")
for verdict_name in os.listdir(verdicts_root):
    if not verdict_name.endswith(".json"):
        continue
    existing = validate_existing_readiness_verdict("verdicts/" + verdict_name)
    if existing is not None and existing == (audit_version, "BLOCKED"):
        reject("audit_version already has a canonical BLOCKED readiness verdict")

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
    if label == "result" and validation_phase in {"after", "final"}:
        if matches != [target_name]:
            reject("reserved result directory is missing or case-colliding")
        result_path = os.path.join(parent, target_name)
        info = os.lstat(result_path)
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
            reject("reserved result path is not a regular directory")
        result_members = os.listdir(result_path)
        if validation_phase == "after" and result_members:
            reject("reserved result directory is not empty")
        if validation_phase == "final":
            expected_member = manifest["output_id"] + ".json"
            if result_members != [expected_member]:
                reject("published result directory does not contain exactly the bound candidate")
            member_info = os.lstat(os.path.join(result_path, expected_member))
            if (stat.S_ISLNK(member_info.st_mode) or not stat.S_ISREG(member_info.st_mode) or
                    member_info.st_nlink != 1):
                reject("published result candidate is a symlink, special file, or hard-linked")
    elif matches:
        reject(label + " path collides with an existing object")

for identity, directory in directory_identities.items():
    current_info = os.lstat(directory)
    if stat.S_ISLNK(current_info.st_mode) or (current_info.st_dev, current_info.st_ino) != identity:
        reject("directory identity changed before packet validation completed")
final_packet_root = os.lstat(packet_root)
if (final_packet_root.st_dev, final_packet_root.st_ino) != packet_root_identity:
    reject("packet root identity changed before validation completed")

state = {
    "manifest_sha256": hashlib.sha256(manifest_raw).hexdigest(),
    "attempt_id": manifest["attempt_id"],
    "output_id": manifest["output_id"],
    "audit_version": audit_version,
    "corrected_audit_path": expected_corrected,
    "corrected_audit_sha256": entry_map[expected_corrected],
    "review_question": manifest["review_question"],
    "allowlist": manifest["allowlist"],
    "read_bindings": read_bindings,
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
  readiness_routing="$readiness_tmp/model-routing.json"
  readiness_schema_snapshot="$readiness_tmp/challenger-verdict.schema.json"
  readiness_control_bindings="$readiness_tmp/control-bindings.json"
  python3 - "$readiness_control_bindings" "$ROUTING" "$readiness_routing" \
    "$readiness_schema" "$readiness_schema_snapshot" <<'PY' || exit 1
import hashlib
import json
import os
import stat
import sys

def reject(message):
    raise SystemExit("run-cold-reviewer: readiness JSON preflight " + message)

def pairs(label):
    def hook(items):
        result = {}
        for key, value in items:
            if key in result:
                reject(label + " contains duplicate JSON key: " + key)
            result[key] = value
        return result
    return hook

binding_out = sys.argv[1]

def secure_read(path):
    canonical_path = os.path.realpath(path)
    parent = os.path.dirname(canonical_path)
    try:
        supplied_before = os.lstat(path)
        supplied_target_before = os.stat(path)
        parent_before = os.lstat(parent)
        path_before = os.lstat(canonical_path)
        flags = (os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) |
                 getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_CLOEXEC", 0))
        descriptor = os.open(canonical_path, flags)
    except OSError as exc:
        reject("cannot read %s: %s" % (path, exc))
    try:
        opened_before = os.fstat(descriptor)
        if (stat.S_ISLNK(path_before.st_mode) or not stat.S_ISREG(path_before.st_mode) or
                not stat.S_ISREG(opened_before.st_mode) or path_before.st_nlink != 1 or
                opened_before.st_nlink != 1 or
                (path_before.st_dev, path_before.st_ino) !=
                (opened_before.st_dev, opened_before.st_ino)):
            reject(path + " is not one exact unaliased regular file")
        chunks = []
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
        raw = b"".join(chunks)
        opened_after = os.fstat(descriptor)
    finally:
        os.close(descriptor)
    try:
        path_after = os.lstat(path)
        canonical_after = os.lstat(canonical_path)
        supplied_target_after = os.stat(path)
        parent_after = os.lstat(parent)
    except OSError as exc:
        reject("secure binding disappeared for %s: %s" % (path, exc))
    identity = (opened_before.st_dev, opened_before.st_ino)
    if (stat.S_ISLNK(supplied_before.st_mode) or
            (supplied_target_before.st_dev, supplied_target_before.st_ino) != identity or
            (opened_after.st_dev, opened_after.st_ino) != identity or
            opened_after.st_nlink != 1 or opened_after.st_size != len(raw) or
            (path_after.st_dev, path_after.st_ino) != identity or
            (canonical_after.st_dev, canonical_after.st_ino) != identity or
            (supplied_target_after.st_dev, supplied_target_after.st_ino) != identity or
            canonical_after.st_nlink != 1 or not stat.S_ISREG(canonical_after.st_mode) or
            stat.S_ISLNK(parent_before.st_mode) or
            not stat.S_ISDIR(parent_before.st_mode) or
            (parent_after.st_dev, parent_after.st_ino) !=
            (parent_before.st_dev, parent_before.st_ino)):
        reject(path + " identity, bytes, link count, or parent changed while read")
    return raw, {
        "canonical_path": canonical_path, "dev": opened_after.st_dev,
        "ino": opened_after.st_ino, "parent_dev": parent_after.st_dev,
        "parent_ino": parent_after.st_ino, "sha256": hashlib.sha256(raw).hexdigest(),
        "size": len(raw), "supplied_path": path,
    }

bindings = []
for source, destination in zip(sys.argv[2::2], sys.argv[3::2]):
    raw, binding = secure_read(source)
    bindings.append(binding)
    if raw.startswith(b"\xef\xbb\xbf"):
        reject(source + " has a byte order mark")
    try:
        text = raw.decode("utf-8")
        decoder = json.JSONDecoder(
            object_pairs_hook=pairs(source),
            parse_constant=lambda value: reject(source + " contains non-RFC-8259 constant: " + value),
        )
        start = 0
        while start < len(text) and text[start] in " \t\r\n":
            start += 1
        unused, end = decoder.raw_decode(text, start)
    except (UnicodeDecodeError, ValueError, json.JSONDecodeError) as exc:
        reject("invalid JSON in %s: %s" % (source, exc))
    if any(character not in " \t\r\n" for character in text[end:]):
        reject(source + " has trailing content or non-RFC-8259 whitespace")
    try:
        descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            offset = 0
            while offset < len(raw):
                offset += os.write(descriptor, raw[offset:])
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    except OSError as exc:
        reject("cannot retain secure snapshot of %s: %s" % (source, exc))
try:
    with open(binding_out, "x", encoding="utf-8") as handle:
        json.dump(bindings, handle, ensure_ascii=True, separators=(",", ":"), sort_keys=True)
        handle.write("\n")
except OSError as exc:
    reject("cannot retain secure readiness control bindings: %s" % exc)
PY
  readiness_schema="$readiness_schema_snapshot"
  jq -e '
    type == "object"
    and (.runtime == "claude" or .runtime == "openai" or .runtime == "codex")
    and (.roles | type == "object")
    and (.roles.challenger | type == "object")
    and (.roles.challenger.model | type == "string" and length > 0)
    and (if (.runtime == "openai" or .runtime == "codex")
         then (.roles.challenger.reasoningEffort
               | type == "string"
               and (. == "none" or . == "minimal" or . == "low" or . == "medium"
                    or . == "high" or . == "xhigh" or . == "max" or . == "ultra"))
         else true
         end)
  ' "$readiness_routing" >/dev/null 2>&1 \
    || fail "readiness audit model-routing.json lacks a valid Challenger route"

  runtime="$(jq -er '.runtime' "$readiness_routing")" \
    || fail "cannot read readiness reviewer runtime"
  case "$runtime" in
    openai|codex) runtime="openai" ;;
    claude) ;;
    *) fail "reviewer host '$runtime' has no cold-reviewer adapter" ;;
  esac
  model="$(jq -er '.roles.challenger.model' "$readiness_routing")" \
    || fail "cannot read readiness Challenger model"
  reasoning_effort="$(jq -r '.roles.challenger.reasoningEffort // empty' "$readiness_routing")" \
    || fail "cannot read readiness Challenger reasoning effort"

  target_repo=""
  if [ "$runtime" = "openai" ]; then
    target_repo="$(python3 - "$RUN_DIR/state.json" "$readiness_tmp/state-control-binding.json" <<'PY'
import hashlib
import json
import os
import stat
import sys

state_path, binding_out = sys.argv[1:]

def reject(message):
    raise SystemExit("run-cold-reviewer: readiness Codex target deny " + message)

def pairs_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            reject("state.json contains duplicate key: " + key)
        result[key] = value
    return result

try:
    canonical_state = os.path.realpath(state_path)
    parent = os.path.dirname(canonical_state)
    supplied_before = os.lstat(state_path)
    supplied_target_before = os.stat(state_path)
    parent_before = os.lstat(parent)
    path_before = os.lstat(canonical_state)
    flags = (os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) |
             getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_CLOEXEC", 0))
    descriptor = os.open(canonical_state, flags)
except OSError as exc:
    reject("cannot read state.json: %s" % exc)
try:
    opened_before = os.fstat(descriptor)
    if (stat.S_ISLNK(path_before.st_mode) or not stat.S_ISREG(path_before.st_mode) or
            not stat.S_ISREG(opened_before.st_mode) or path_before.st_nlink != 1 or
            opened_before.st_nlink != 1 or
            (path_before.st_dev, path_before.st_ino) !=
            (opened_before.st_dev, opened_before.st_ino)):
        reject("state.json is not one exact unaliased regular file")
    chunks = []
    while True:
        chunk = os.read(descriptor, 1024 * 1024)
        if not chunk:
            break
        chunks.append(chunk)
    raw = b"".join(chunks)
    opened_after = os.fstat(descriptor)
finally:
    os.close(descriptor)
try:
    path_after = os.lstat(state_path)
    canonical_after = os.lstat(canonical_state)
    supplied_target_after = os.stat(state_path)
    parent_after = os.lstat(parent)
except OSError as exc:
    reject("state.json secure binding disappeared: %s" % exc)
identity = (opened_before.st_dev, opened_before.st_ino)
if (stat.S_ISLNK(supplied_before.st_mode) or
        (supplied_target_before.st_dev, supplied_target_before.st_ino) != identity or
        (opened_after.st_dev, opened_after.st_ino) != identity or
        opened_after.st_nlink != 1 or opened_after.st_size != len(raw) or
        (path_after.st_dev, path_after.st_ino) != identity or
        (canonical_after.st_dev, canonical_after.st_ino) != identity or
        (supplied_target_after.st_dev, supplied_target_after.st_ino) != identity or
        canonical_after.st_nlink != 1 or not stat.S_ISREG(canonical_after.st_mode) or
        stat.S_ISLNK(parent_before.st_mode) or
        not stat.S_ISDIR(parent_before.st_mode) or
        (parent_after.st_dev, parent_after.st_ino) !=
        (parent_before.st_dev, parent_before.st_ino)):
    reject("state.json identity, bytes, link count, or parent changed while read")
if raw.startswith(b"\xef\xbb\xbf"):
    reject("state.json has a byte order mark")
try:
    text = raw.decode("utf-8")
    decoder = json.JSONDecoder(
        object_pairs_hook=pairs_object,
        parse_constant=lambda value: reject("state.json contains non-RFC-8259 constant: " + value),
    )
    start = 0
    while start < len(text) and text[start] in " \t\r\n":
        start += 1
    state, end = decoder.raw_decode(text, start)
except (UnicodeDecodeError, ValueError, json.JSONDecodeError) as exc:
    reject("state.json is invalid JSON: %s" % exc)
if any(character not in " \t\r\n" for character in text[end:]):
    reject("state.json contains trailing content or non-RFC-8259 whitespace")
if not isinstance(state, dict):
    reject("state.json is not an object")
target = state.get("target_repo")
if not isinstance(target, str) or not target or not os.path.isabs(target):
    reject("target_repo must be one nonempty absolute path string")
canonical = os.path.realpath(target)
try:
    target_mode = os.stat(canonical).st_mode
except OSError as exc:
    reject("target_repo cannot be resolved: %s" % exc)
if not stat.S_ISDIR(target_mode):
    reject("target_repo does not resolve to an existing directory")
try:
    with open(binding_out, "x", encoding="utf-8") as handle:
        json.dump({
            "canonical_path": canonical_state, "dev": opened_after.st_dev,
            "ino": opened_after.st_ino, "parent_dev": parent_after.st_dev,
            "parent_ino": parent_after.st_ino, "sha256": hashlib.sha256(raw).hexdigest(),
            "size": len(raw), "supplied_path": state_path,
        }, handle, ensure_ascii=True, separators=(",", ":"), sort_keys=True)
        handle.write("\n")
except OSError as exc:
    reject("cannot retain state.json secure binding: %s" % exc)
print(target)
PY
)" || exit 1

    codex_deny_locations="$readiness_tmp/codex-deny-locations.jsonl"
    : > "$codex_deny_locations" || fail "cannot initialize readiness Codex deny set"
    record_readiness_location() {
      location="$1"
      required_kind="$2"
      location_label="$3"
      python3 - "$location" "$required_kind" "$location_label" <<'PY' >> "$codex_deny_locations" || exit 1
import json
import os
import pathlib
import stat
import sys

location, required_kind, label = sys.argv[1:]

def reject(message):
    raise SystemExit("run-cold-reviewer: readiness Codex deny location %s %s" % (label, message))

if not location or not os.path.isabs(location):
    reject("must be one nonempty absolute path")
if "\n" in location or "\r" in location or "\x00" in location:
    reject("contains a forbidden control byte")
try:
    canonical = str(pathlib.Path(location).resolve(strict=True))
    info = os.stat(canonical)
except (OSError, RuntimeError) as exc:
    reject("cannot be physically resolved: %s" % exc)
if required_kind == "directory" and not stat.S_ISDIR(info.st_mode):
    reject("does not resolve to an existing directory")
if required_kind == "regular" and not stat.S_ISREG(info.st_mode):
    reject("does not resolve to an existing regular file")
if required_kind not in {"directory", "regular", "any"}:
    reject("has an invalid internal kind")
print(json.dumps({"canonical": canonical, "supplied": location},
                 ensure_ascii=True, separators=(",", ":"), sort_keys=True))
PY
    }

    record_readiness_location "$RUN_DIR" directory RUN_DIR
    record_readiness_location "$CTX" directory CTX
    record_readiness_location "$ROOT" directory framework-root
    record_readiness_location "${HOME:-}" directory HOME
    record_readiness_location "$target_repo" directory target_repo
    [ -z "${CODEX_HOME:-}" ] || record_readiness_location "$CODEX_HOME" directory CODEX_HOME
    [ -z "${CODEX_SESSION_ROOT:-}" ] || record_readiness_location "$CODEX_SESSION_ROOT" any CODEX_SESSION_ROOT
    [ -z "${CODEX_CONFIG_ROOT:-}" ] || record_readiness_location "$CODEX_CONFIG_ROOT" any CODEX_CONFIG_ROOT
    [ -z "${CLAUDE_CONFIG_DIR:-}" ] || record_readiness_location "$CLAUDE_CONFIG_DIR" directory CLAUDE_CONFIG_DIR
    [ -z "${BUREAU_CLAUDE_PROJECTS_DIR:-}" ] || record_readiness_location "$BUREAU_CLAUDE_PROJECTS_DIR" directory BUREAU_CLAUDE_PROJECTS_DIR
    [ -z "${BUREAU_POINTER_DIR:-}" ] || record_readiness_location "$BUREAU_POINTER_DIR" directory BUREAU_POINTER_DIR
    [ -z "${BUREAU_REVIEWER_SESSION_ROOT:-}" ] || record_readiness_location "$BUREAU_REVIEWER_SESSION_ROOT" any BUREAU_REVIEWER_SESSION_ROOT
    [ -z "${BUREAU_REVIEWER_CONFIG_ROOT:-}" ] || record_readiness_location "$BUREAU_REVIEWER_CONFIG_ROOT" any BUREAU_REVIEWER_CONFIG_ROOT
    [ -z "${BUREAU_REVIEWER_UNSTAGED_SENTINEL:-}" ] || record_readiness_location "$BUREAU_REVIEWER_UNSTAGED_SENTINEL" any BUREAU_REVIEWER_UNSTAGED_SENTINEL
    [ -z "${UNSTAGED_SENTINEL:-}" ] || record_readiness_location "$UNSTAGED_SENTINEL" any UNSTAGED_SENTINEL
  fi

  publication_identities="$readiness_tmp/publication-identities.json"
  candidate_binding="$readiness_tmp/published-candidate-binding.json"
  custody_channel="$readiness_tmp/custody-channel"
  mkdir -m 700 "$custody_channel" \
    || fail "cannot create readiness custody command channel"
  custody_token="$(python3 -c 'import secrets; print(secrets.token_hex(32))')" \
    || fail "cannot create readiness custody capability"
  custody_stderr="$readiness_tmp/custody-stderr.log"
  python3 - "$RUN_DIR/audit/reviews" "${attempt_id}-result" "$RUN_DIR/verdicts" \
    "$publication_identities" "$candidate_binding" "$custody_channel" "$custody_token" \
    > "$readiness_tmp/custody-stdout.log" 2> "$custody_stderr" <<'PY' &
import hashlib
import json
import os
import re
import secrets
import stat
import sys
import time

reviews_parent, result_name, verdict_parent, identities_path, binding_path, channel_path, token = sys.argv[1:]
if not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?-result", result_name):
    raise SystemExit("run-cold-reviewer: readiness result reservation basename is unsafe")

directory_flags = (os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) |
                   getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0))

def open_anchored(path, label):
    try:
        path_info = os.lstat(path)
        descriptor = os.open(path, directory_flags)
        descriptor_info = os.fstat(descriptor)
    except OSError as exc:
        raise SystemExit("run-cold-reviewer: readiness %s cannot be opened: %s" % (label, exc))
    if (stat.S_ISLNK(path_info.st_mode) or not stat.S_ISDIR(path_info.st_mode) or
            not stat.S_ISDIR(descriptor_info.st_mode) or
            (path_info.st_dev, path_info.st_ino) != (descriptor_info.st_dev, descriptor_info.st_ino)):
        os.close(descriptor)
        raise SystemExit("run-cold-reviewer: readiness %s identity is unsafe" % label)
    return descriptor, (descriptor_info.st_dev, descriptor_info.st_ino)

def verify_directory(descriptor, path, expected, label):
    try:
        descriptor_info = os.fstat(descriptor)
        path_info = os.lstat(path)
    except OSError as exc:
        raise RuntimeError("%s is unavailable: %s" % (label, exc))
    if (not stat.S_ISDIR(descriptor_info.st_mode) or stat.S_ISLNK(path_info.st_mode) or
            not stat.S_ISDIR(path_info.st_mode) or
            (descriptor_info.st_dev, descriptor_info.st_ino) != expected or
            (path_info.st_dev, path_info.st_ino) != expected):
        raise RuntimeError(label + " identity changed")

def read_regular_fd(descriptor, label):
    before = os.fstat(descriptor)
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
        raise RuntimeError(label + " is not one unaliased regular file")
    os.lseek(descriptor, 0, os.SEEK_SET)
    chunks = []
    while True:
        chunk = os.read(descriptor, 1024 * 1024)
        if not chunk:
            break
        chunks.append(chunk)
    raw = b"".join(chunks)
    after = os.fstat(descriptor)
    if ((before.st_dev, before.st_ino, before.st_size, before.st_nlink) !=
            (after.st_dev, after.st_ino, after.st_size, after.st_nlink) or
            after.st_nlink != 1 or after.st_size != len(raw)):
        raise RuntimeError(label + " changed while read")
    return raw, after

def read_anchored_member(directory, parent_path, expected_identity, name, label,
                         maximum=64 * 1024 * 1024):
    verify_directory(directory, parent_path, expected_identity, label + " parent")
    try:
        path_before = os.stat(name, dir_fd=directory, follow_symlinks=False)
        flags = (os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) |
                 getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_CLOEXEC", 0))
        descriptor = os.open(name, flags, dir_fd=directory)
    except OSError as exc:
        raise RuntimeError("%s cannot be securely opened: %s" % (label, exc))
    try:
        opened_before = os.fstat(descriptor)
        if (not stat.S_ISREG(path_before.st_mode) or path_before.st_nlink != 1 or
                not stat.S_ISREG(opened_before.st_mode) or opened_before.st_nlink != 1 or
                (path_before.st_dev, path_before.st_ino) !=
                (opened_before.st_dev, opened_before.st_ino)):
            raise RuntimeError(label + " is not one exact unaliased regular file")
        chunks = []
        size = 0
        while True:
            chunk = os.read(descriptor, min(65536, maximum + 1 - size))
            if not chunk:
                break
            chunks.append(chunk)
            size += len(chunk)
            if size > maximum:
                raise RuntimeError(label + " exceeds the bounded channel size")
        raw = b"".join(chunks)
        opened_after = os.fstat(descriptor)
    except Exception:
        os.close(descriptor)
        raise
    try:
        linked_after = os.stat(name, dir_fd=directory, follow_symlinks=False)
        canonical_after = os.lstat(os.path.join(parent_path, name))
        verify_directory(directory, parent_path, expected_identity, label + " parent")
    except Exception:
        os.close(descriptor)
        raise
    identity = (opened_before.st_dev, opened_before.st_ino)
    if ((opened_after.st_dev, opened_after.st_ino, opened_after.st_size,
         opened_after.st_nlink) !=
            (opened_before.st_dev, opened_before.st_ino, opened_before.st_size,
             opened_before.st_nlink) or opened_after.st_nlink != 1 or
            opened_after.st_size != len(raw) or
            (linked_after.st_dev, linked_after.st_ino) != identity or
            not stat.S_ISREG(linked_after.st_mode) or linked_after.st_nlink != 1 or
            (canonical_after.st_dev, canonical_after.st_ino) != identity or
            not stat.S_ISREG(canonical_after.st_mode) or canonical_after.st_nlink != 1):
        os.close(descriptor)
        raise RuntimeError(label + " identity, bytes, link count, or path binding changed")
    observed = {
        "dev": opened_after.st_dev, "ino": opened_after.st_ino,
        "parent_dev": expected_identity[0], "parent_ino": expected_identity[1],
        "sha256": hashlib.sha256(raw).hexdigest(), "size": len(raw), "name": name,
    }
    return descriptor, raw, observed

def strict_json(raw, label):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise RuntimeError(label + " contains a duplicate JSON key")
            result[key] = value
        return result
    if raw.startswith(b"\xef\xbb\xbf"):
        raise RuntimeError(label + " contains a byte order mark")
    try:
        text = raw.decode("utf-8")
        decoder = json.JSONDecoder(
            object_pairs_hook=pairs,
            parse_constant=lambda value: (_ for _ in ()).throw(
                RuntimeError(label + " contains a non-RFC-8259 constant")),
        )
        start = 0
        while start < len(text) and text[start] in " \t\r\n":
            start += 1
        value, end = decoder.raw_decode(text, start)
    except (UnicodeDecodeError, ValueError, json.JSONDecodeError) as exc:
        raise RuntimeError("%s is invalid JSON: %s" % (label, exc))
    if any(character not in " \t\r\n" for character in text[end:]):
        raise RuntimeError(label + " contains trailing data or non-RFC-8259 whitespace")
    return value

def read_private_source(path):
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0)
    descriptor = os.open(path, flags)
    try:
        return read_regular_fd(descriptor, "private publication source")[0]
    finally:
        os.close(descriptor)

def write_private(path, raw):
    with open(path, "wb") as handle:
        handle.write(raw)

def publish_bytes(raw, directory, parent_path, expected_identity, name):
    verify_directory(directory, parent_path, expected_identity, "publication parent")
    for existing in os.listdir(directory):
        if existing == name or existing.lower() == name.lower():
            raise RuntimeError("no-clobber publication collision: " + name)
    temporary = ".readiness-publish-%s.tmp" % secrets.token_hex(12)
    published_identity = None
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                         0o600, dir_fd=directory)
    try:
        offset = 0
        while offset < len(raw):
            offset += os.write(descriptor, raw[offset:])
        os.fsync(descriptor)
        temporary_info = os.fstat(descriptor)
        if (not stat.S_ISREG(temporary_info.st_mode) or temporary_info.st_nlink != 1 or
                temporary_info.st_size != len(raw)):
            raise RuntimeError("publication temporary identity or bytes changed")
        verify_directory(directory, parent_path, expected_identity, "publication parent")
        os.link(temporary, name, src_dir_fd=directory, dst_dir_fd=directory,
                follow_symlinks=False)
        linked_info = os.stat(name, dir_fd=directory, follow_symlinks=False)
        if ((linked_info.st_dev, linked_info.st_ino) !=
                (temporary_info.st_dev, temporary_info.st_ino) or
                not stat.S_ISREG(linked_info.st_mode)):
            raise RuntimeError("published member identity differs from linked temporary")
        published_identity = (temporary_info.st_dev, temporary_info.st_ino)
        os.fsync(directory)
        verify_directory(directory, parent_path, expected_identity, "publication parent")
    finally:
        os.close(descriptor)
        try:
            os.unlink(temporary, dir_fd=directory)
        except FileNotFoundError:
            pass
    return published_identity

reviews_fd, reviews_identity = open_anchored(reviews_parent, "reviews parent")
try:
    for existing in os.listdir(reviews_fd):
        if existing == result_name or existing.lower() == result_name.lower():
            raise SystemExit("run-cold-reviewer: readiness result reservation collides: " + result_name)
    try:
        os.mkdir(result_name, 0o700, dir_fd=reviews_fd)
    except OSError as exc:
        raise SystemExit("run-cold-reviewer: cannot exclusively reserve readiness result directory: %s" % exc)
    try:
        result_fd = os.open(result_name, directory_flags, dir_fd=reviews_fd)
        result_info = os.fstat(result_fd)
        linked_info = os.stat(result_name, dir_fd=reviews_fd, follow_symlinks=False)
        current_reviews = os.lstat(reviews_parent)
    except OSError as exc:
        raise SystemExit("run-cold-reviewer: cannot bind reserved readiness result directory: %s" % exc)
    if (not stat.S_ISDIR(result_info.st_mode) or not stat.S_ISDIR(linked_info.st_mode) or
            (result_info.st_dev, result_info.st_ino) != (linked_info.st_dev, linked_info.st_ino)):
        raise SystemExit("run-cold-reviewer: reserved readiness result identity is unsafe")
    if ((current_reviews.st_dev, current_reviews.st_ino) != reviews_identity or
            stat.S_ISLNK(current_reviews.st_mode)):
        raise SystemExit("run-cold-reviewer: reviews parent identity changed during result reservation")
finally:
    os.close(reviews_fd)

verdict_fd, verdict_identity = open_anchored(verdict_parent, "verdict parent")
result_path = os.path.join(reviews_parent, result_name)
result_identity = (result_info.st_dev, result_info.st_ino)
identities = {"candidate": {
    "dev": result_info.st_dev,
    "ino": result_info.st_ino,
    "path": result_path,
}, "verdict": {
    "dev": verdict_identity[0],
    "ino": verdict_identity[1],
    "path": verdict_parent,
}}
with open(identities_path, "x", encoding="utf-8") as handle:
    json.dump(identities, handle, ensure_ascii=True, separators=(",", ":"), sort_keys=True)
    handle.write("\n")

candidate_fd = None
candidate_name = None
candidate_raw = None
candidate_observed = None
verdict_member_fd = None
verdict_name = None
verdict_raw = None
verdict_observed = None

def validate_candidate(output_path=None):
    global candidate_raw
    if candidate_fd is None or candidate_observed is None:
        raise RuntimeError("candidate has not been published")
    verify_directory(result_fd, result_path, result_identity, "retained result parent")
    raw, info = read_regular_fd(candidate_fd, "retained candidate")
    linked = os.stat(candidate_name, dir_fd=result_fd, follow_symlinks=False)
    canonical = os.lstat(os.path.join(result_path, candidate_name))
    observed = {
        "dev": info.st_dev, "ino": info.st_ino, "name": candidate_name,
        "parent_dev": result_identity[0], "parent_ino": result_identity[1],
        "sha256": hashlib.sha256(raw).hexdigest(), "size": len(raw),
    }
    if (not stat.S_ISREG(linked.st_mode) or linked.st_nlink != 1 or
            not stat.S_ISREG(canonical.st_mode) or canonical.st_nlink != 1 or
            (linked.st_dev, linked.st_ino) != (info.st_dev, info.st_ino) or
            (canonical.st_dev, canonical.st_ino) != (info.st_dev, info.st_ino) or
            observed != candidate_observed or raw != candidate_raw):
        raise RuntimeError("candidate identity, bytes, hash, link count, or path binding changed")
    if output_path:
        write_private(output_path, raw)

def validate_verdict():
    if verdict_member_fd is None or verdict_observed is None:
        raise RuntimeError("canonical verdict has not been published")
    verify_directory(verdict_fd, verdict_parent, verdict_identity, "retained verdict parent")
    raw, info = read_regular_fd(verdict_member_fd, "retained canonical verdict")
    linked = os.stat(verdict_name, dir_fd=verdict_fd, follow_symlinks=False)
    canonical = os.lstat(os.path.join(verdict_parent, verdict_name))
    observed = {
        "dev": info.st_dev, "ino": info.st_ino, "name": verdict_name,
        "parent_dev": verdict_identity[0], "parent_ino": verdict_identity[1],
        "sha256": hashlib.sha256(raw).hexdigest(), "size": len(raw),
    }
    if (not stat.S_ISREG(linked.st_mode) or linked.st_nlink != 1 or
            not stat.S_ISREG(canonical.st_mode) or canonical.st_nlink != 1 or
            (linked.st_dev, linked.st_ino) != (info.st_dev, info.st_ino) or
            (canonical.st_dev, canonical.st_ino) != (info.st_dev, info.st_ino) or
            observed != verdict_observed or raw != verdict_raw):
        raise RuntimeError("canonical verdict identity, bytes, hash, link count, or path binding changed")

channel_fd, channel_identity = open_anchored(channel_path, "custody channel")

ready_descriptor = os.open("ready", os.O_WRONLY | os.O_CREAT | os.O_EXCL |
                           getattr(os, "O_CLOEXEC", 0), 0o600, dir_fd=channel_fd)
os.write(ready_descriptor, b"ready\n")
os.fsync(ready_descriptor)
os.close(ready_descriptor)
os.fsync(channel_fd)
seen_nonces = set()
last_sequence = 0
try:
    while True:
        verify_directory(channel_fd, channel_path, channel_identity, "custody channel")
        request_names = sorted(name for name in os.listdir(channel_fd)
                               if re.fullmatch(r"[0-9a-f]{32}\.request", name))
        if not request_names:
            time.sleep(0.01)
            continue
        request_name = request_names[0]
        try:
            pending_request = os.stat(request_name, dir_fd=channel_fd, follow_symlinks=False)
        except FileNotFoundError:
            continue
        if stat.S_ISREG(pending_request.st_mode) and pending_request.st_nlink != 1:
            time.sleep(0.01)
            continue
        request_nonce = request_name[:-8]
        response_name = request_nonce + ".response"
        response_action = "invalid"
        response_sequence = -1
        response_command_token = "invalid"
        stop_after_response = False
        try:
            request_descriptor, request_raw, unused_request_binding = read_anchored_member(
                channel_fd, channel_path, channel_identity, request_name, "custody request",
                maximum=1024 * 1024)
            os.close(request_descriptor)
            os.unlink(request_name, dir_fd=channel_fd)
            request = strict_json(request_raw, "custody request")
            if not isinstance(request, dict) or set(request) != {
                    "action", "arguments", "capability", "command_token", "nonce", "sequence"}:
                raise RuntimeError("custody request has the wrong exact field set")
            response_action = request["action"]
            response_sequence = request["sequence"]
            response_command_token = request["command_token"]
            if request["capability"] != token:
                raise RuntimeError("invalid custody capability")
            if (request["nonce"] != request_nonce or
                    not re.fullmatch(r"[0-9a-f]{32}", request["nonce"] or "") or
                    not re.fullmatch(r"[0-9a-f]{64}", request["command_token"] or "")):
                raise RuntimeError("custody request nonce or command token is invalid")
            if request_nonce in seen_nonces:
                raise RuntimeError("custody request nonce was replayed")
            if type(request["sequence"]) is not int or request["sequence"] != last_sequence + 1:
                raise RuntimeError("custody request sequence is invalid or replayed")
            if not isinstance(request["action"], str) or not isinstance(request["arguments"], list):
                raise RuntimeError("custody request action or arguments type is invalid")
            seen_nonces.add(request_nonce)
            last_sequence = request["sequence"]
            action = request["action"]
            arguments = request["arguments"]
            if action == "status":
                if arguments:
                    raise RuntimeError("status arguments are invalid")
                verify_directory(result_fd, result_path, result_identity, "retained result parent")
            elif action == "check-empty":
                if arguments:
                    raise RuntimeError("check-empty arguments are invalid")
                verify_directory(result_fd, result_path, result_identity, "retained result parent")
                if os.listdir(result_fd):
                    raise RuntimeError("reserved result directory is not empty")
            elif action == "publish-candidate":
                if candidate_fd is not None or len(arguments) != 3:
                    raise RuntimeError("candidate publication state is invalid")
                source, requested_name, reopened_output = arguments
                if not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?\.json", requested_name):
                    raise RuntimeError("candidate basename is unsafe")
                raw = read_private_source(source)
                candidate_published_identity = publish_bytes(
                    raw, result_fd, result_path, result_identity, requested_name)
                flags = (os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) |
                         getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_CLOEXEC", 0))
                candidate_fd = os.open(requested_name, flags, dir_fd=result_fd)
                candidate_name = requested_name
                candidate_raw, info = read_regular_fd(candidate_fd, "published candidate")
                if candidate_raw != raw or (info.st_dev, info.st_ino) != candidate_published_identity:
                    raise RuntimeError("published candidate differs from provider bytes")
                candidate_observed = {
                    "dev": info.st_dev, "ino": info.st_ino, "name": candidate_name,
                    "parent_dev": result_identity[0], "parent_ino": result_identity[1],
                    "sha256": hashlib.sha256(candidate_raw).hexdigest(), "size": len(candidate_raw),
                }
                with open(binding_path, "x", encoding="utf-8") as handle:
                    json.dump(candidate_observed, handle, ensure_ascii=True,
                              separators=(",", ":"), sort_keys=True)
                    handle.write("\n")
                validate_candidate(reopened_output)
            elif action == "validate-candidate":
                if len(arguments) != 1:
                    raise RuntimeError("candidate validation arguments are invalid")
                validate_candidate(arguments[0])
            elif action == "publish-verdict":
                if len(arguments) != 2:
                    raise RuntimeError("verdict publication arguments are invalid")
                source, requested_verdict_name = arguments
                if verdict_member_fd is not None:
                    raise RuntimeError("canonical verdict publication state is invalid")
                validate_candidate()
                source_raw = read_private_source(source)
                verdict_published_identity = publish_bytes(
                    source_raw, verdict_fd, verdict_parent, verdict_identity,
                    requested_verdict_name)
                verdict_name = requested_verdict_name
                verdict_member_fd, verdict_raw, verdict_observed = read_anchored_member(
                    verdict_fd, verdict_parent, verdict_identity, verdict_name,
                    "published canonical verdict")
                if (verdict_raw != source_raw or
                        (verdict_observed["dev"], verdict_observed["ino"]) !=
                        verdict_published_identity):
                    raise RuntimeError("published canonical verdict differs from adapter bytes")
                validate_candidate()
                validate_verdict()
            elif action == "finalize":
                if arguments or verdict_member_fd is None:
                    raise RuntimeError("terminal custody state is invalid")
                validate_candidate()
                validate_verdict()
                stop_after_response = True
            else:
                raise RuntimeError("unknown custody action")
            if verdict_member_fd is not None:
                validate_candidate()
                validate_verdict()
            response = {
                "action": response_action, "command_token": response_command_token,
                "nonce": request_nonce, "ok": True, "sequence": response_sequence,
            }
        except Exception as exc:
            response = {
                "action": response_action, "command_token": response_command_token,
                "error": str(exc), "nonce": request_nonce, "ok": False,
                "sequence": response_sequence,
            }
        response_raw = (json.dumps(response, ensure_ascii=True, separators=(",", ":"),
                                   sort_keys=True) + "\n").encode("utf-8")
        try:
            publish_bytes(response_raw, channel_fd, channel_path, channel_identity, response_name)
        except Exception as exc:
            print("run-cold-reviewer: readiness custody response publication failed: %s" % exc,
                  file=sys.stderr)
            break
        if verdict_member_fd is not None:
            validate_candidate()
            validate_verdict()
        if stop_after_response:
            break
finally:
    if verdict_member_fd is not None:
        os.close(verdict_member_fd)
    if candidate_fd is not None:
        os.close(candidate_fd)
    os.close(channel_fd)
    os.close(result_fd)
    os.close(verdict_fd)
PY
  custody_pid=$!
  custody_sequence=0
  custody_command() {
    action="$1"
    shift
    custody_sequence=$((custody_sequence + 1))
    python3 - "$custody_channel" "$custody_token" "$custody_sequence" "$action" "$@" <<'PY'
import json
import os
import secrets
import stat
import sys
import time

channel_path, capability, sequence_text, action, *arguments = sys.argv[1:]
try:
    sequence = int(sequence_text)
except ValueError:
    raise SystemExit("run-cold-reviewer: readiness custody sequence is invalid")
directory_flags = (os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) |
                   getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0))
try:
    channel_path_info = os.lstat(channel_path)
    channel_fd = os.open(channel_path, directory_flags)
    channel_info = os.fstat(channel_fd)
except OSError as exc:
    raise SystemExit("run-cold-reviewer: readiness custody channel cannot be opened: %s" % exc)
channel_identity = (channel_info.st_dev, channel_info.st_ino)
if (stat.S_ISLNK(channel_path_info.st_mode) or not stat.S_ISDIR(channel_path_info.st_mode) or
        not stat.S_ISDIR(channel_info.st_mode) or
        (channel_path_info.st_dev, channel_path_info.st_ino) != channel_identity):
    raise SystemExit("run-cold-reviewer: readiness custody channel identity is unsafe")

def verify_channel():
    try:
        descriptor_info = os.fstat(channel_fd)
        path_info = os.lstat(channel_path)
    except OSError as exc:
        raise SystemExit("run-cold-reviewer: readiness custody channel disappeared: %s" % exc)
    if (not stat.S_ISDIR(descriptor_info.st_mode) or stat.S_ISLNK(path_info.st_mode) or
            not stat.S_ISDIR(path_info.st_mode) or
            (descriptor_info.st_dev, descriptor_info.st_ino) != channel_identity or
            (path_info.st_dev, path_info.st_ino) != channel_identity):
        raise SystemExit("run-cold-reviewer: readiness custody channel identity changed")

def strict_json(raw):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError("duplicate JSON key")
            result[key] = value
        return result
    if raw.startswith(b"\xef\xbb\xbf"):
        raise ValueError("byte order mark")
    text = raw.decode("utf-8")
    decoder = json.JSONDecoder(
        object_pairs_hook=pairs,
        parse_constant=lambda value: (_ for _ in ()).throw(ValueError("invalid constant")),
    )
    start = 0
    while start < len(text) and text[start] in " \t\r\n":
        start += 1
    value, end = decoder.raw_decode(text, start)
    if any(character not in " \t\r\n" for character in text[end:]):
        raise ValueError("trailing data or non-RFC-8259 whitespace")
    return value

for unused in range(500):
    try:
        verify_channel()
        ready_path_info = os.stat("ready", dir_fd=channel_fd, follow_symlinks=False)
        ready_fd = os.open("ready", os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) |
                           getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_CLOEXEC", 0),
                           dir_fd=channel_fd)
        ready_info = os.fstat(ready_fd)
        ready_raw = os.read(ready_fd, 16)
        ready_after = os.fstat(ready_fd)
        os.close(ready_fd)
        if (stat.S_ISREG(ready_info.st_mode) and ready_info.st_nlink == 1 and
                (ready_info.st_dev, ready_info.st_ino) ==
                (ready_path_info.st_dev, ready_path_info.st_ino) and
                (ready_after.st_dev, ready_after.st_ino, ready_after.st_nlink) ==
                (ready_info.st_dev, ready_info.st_ino, ready_info.st_nlink) and
                ready_raw == b"ready\n"):
            break
    except (FileNotFoundError, OSError):
        pass
    time.sleep(0.01)
else:
    raise SystemExit("run-cold-reviewer: readiness custody helper did not become ready")
nonce = secrets.token_hex(16)
command_token = secrets.token_hex(32)
request_name = nonce + ".request"
request_temporary = nonce + ".request.tmp"
response_name = nonce + ".response"
request_raw = (json.dumps({
    "action": action, "arguments": arguments, "capability": capability,
    "command_token": command_token, "nonce": nonce, "sequence": sequence,
}, ensure_ascii=True, separators=(",", ":"), sort_keys=True) + "\n").encode("utf-8")
verify_channel()
descriptor = os.open(request_temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL |
                     getattr(os, "O_CLOEXEC", 0), 0o600, dir_fd=channel_fd)
try:
    offset = 0
    while offset < len(request_raw):
        offset += os.write(descriptor, request_raw[offset:])
    os.fsync(descriptor)
finally:
    os.close(descriptor)
try:
    verify_channel()
    os.link(request_temporary, request_name, src_dir_fd=channel_fd, dst_dir_fd=channel_fd,
            follow_symlinks=False)
    os.fsync(channel_fd)
    verify_channel()
finally:
    try:
        os.unlink(request_temporary, dir_fd=channel_fd)
    except FileNotFoundError:
        pass
aliased_response_polls = 0
for unused in range(3000):
    try:
        verify_channel()
        path_before = os.stat(response_name, dir_fd=channel_fd, follow_symlinks=False)
        if not stat.S_ISREG(path_before.st_mode):
            raise SystemExit("run-cold-reviewer: readiness custody response is not a regular file")
        if path_before.st_nlink != 1:
            aliased_response_polls += 1
            if aliased_response_polls > 100:
                raise SystemExit("run-cold-reviewer: readiness custody response is hard-linked")
            time.sleep(0.01)
            continue
        descriptor = os.open(response_name, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) |
                             getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_CLOEXEC", 0),
                             dir_fd=channel_fd)
        break
    except FileNotFoundError:
        time.sleep(0.01)
else:
    raise SystemExit("run-cold-reviewer: readiness custody helper did not respond")
try:
    before = os.fstat(descriptor)
    if (not stat.S_ISREG(path_before.st_mode) or path_before.st_nlink != 1 or
            not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or
            (path_before.st_dev, path_before.st_ino) != (before.st_dev, before.st_ino)):
        raise ValueError("response is not one exact unaliased regular file")
    chunks = []
    size = 0
    while True:
        chunk = os.read(descriptor, min(65536, 1024 * 1024 + 1 - size))
        if not chunk:
            break
        chunks.append(chunk)
        size += len(chunk)
        if size > 1024 * 1024:
            raise ValueError("response exceeds bounded channel size")
    raw = b"".join(chunks)
    after = os.fstat(descriptor)
except Exception as exc:
    raise SystemExit("run-cold-reviewer: invalid readiness custody response: %s" % exc)
finally:
    os.close(descriptor)
try:
    linked_after = os.stat(response_name, dir_fd=channel_fd, follow_symlinks=False)
    canonical_after = os.lstat(os.path.join(channel_path, response_name))
    verify_channel()
    if ((after.st_dev, after.st_ino, after.st_size, after.st_nlink) !=
            (before.st_dev, before.st_ino, before.st_size, before.st_nlink) or
            after.st_nlink != 1 or after.st_size != len(raw) or
            (linked_after.st_dev, linked_after.st_ino) != (after.st_dev, after.st_ino) or
            not stat.S_ISREG(linked_after.st_mode) or linked_after.st_nlink != 1 or
            (canonical_after.st_dev, canonical_after.st_ino) != (after.st_dev, after.st_ino) or
            not stat.S_ISREG(canonical_after.st_mode) or canonical_after.st_nlink != 1):
        raise ValueError("response identity, bytes, link count, or path binding changed")
    response = strict_json(raw)
except Exception as exc:
    raise SystemExit("run-cold-reviewer: invalid readiness custody response: %s" % exc)
finally:
    try:
        os.unlink(response_name, dir_fd=channel_fd)
    except FileNotFoundError:
        pass
    os.close(channel_fd)
expected_keys = ({"action", "command_token", "nonce", "ok", "sequence"} if response.get("ok") is True
                 else {"action", "command_token", "error", "nonce", "ok", "sequence"})
if (not isinstance(response, dict) or set(response) != expected_keys or
        response.get("action") != action or response.get("command_token") != command_token or
        response.get("nonce") != nonce or response.get("sequence") != sequence):
    raise SystemExit("run-cold-reviewer: invalid readiness custody response binding")
if response.get("ok") is not True:
    raise SystemExit("run-cold-reviewer: readiness custody failure: " + str(response.get("error")))
PY
  }
  if ! custody_command status; then
    sed -n '1,20p' "$custody_stderr" >&2
    exit 1
  fi

  candidate_schema="$readiness_tmp/candidate-schema.json"
  jq -e '
    del(.properties.verdict, .properties.timestamp)
    | .required = ["attempt_id", "review_mode", "reviewed_artifacts", "blocker_ids", "blockers", "warnings"]
    | .properties.reviewed_artifacts.items = .properties.reviewed_artifacts.items.oneOf[0]
    | .properties.blockers.items.additionalProperties = false
    | .properties.warnings.items.additionalProperties = false
  ' "$readiness_schema" > "$candidate_schema" \
    || fail "cannot derive readiness candidate schema"

  build_readiness_prompt() {
    prompt_root="$1"
    question="$(jq -er '.review_question' "$packet_state_before")" \
      || fail "cannot read validated readiness review question"
    printf '%s' "You are The Challenger performing an isolated Codebase Readiness Audit verification. Read ${prompt_root}/packet.json, then read only the regular packet-relative payload files in its allowlist beneath ${prompt_root}. Do not open any path absent from that allowlist, use network access, or seek live run, repository, framework, home, configuration, or session data. Apply the staged self-contained readiness reviewer slice and answer this bounded question: ${question} Return only the exact six-field structured candidate described by the packet contract; do not include verdict or timestamp and do not write any file."
  }

  extract_claude_candidate() {
    raw="$1"
    out="$2"
    python3 - "$raw" "$out" <<'PY'
import json
import sys

source, destination = sys.argv[1:]

def reject(message):
    raise SystemExit("run-cold-reviewer: Claude readiness response " + message)

def pairs_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            reject("contains duplicate JSON key: " + key)
        result[key] = value
    return result

try:
    raw = open(source, "rb").read()
except OSError as exc:
    reject("cannot be read: %s" % exc)
if raw.startswith(b"\xef\xbb\xbf"):
    reject("contains a byte order mark")
try:
    text = raw.decode("utf-8")
    decoder = json.JSONDecoder(
        object_pairs_hook=pairs_object,
        parse_constant=lambda value: reject("contains non-RFC-8259 constant: " + value),
    )
    start = 0
    while start < len(text) and text[start] in " \t\r\n":
        start += 1
    value, end = decoder.raw_decode(text, start)
except (UnicodeDecodeError, ValueError, json.JSONDecodeError) as exc:
    reject("is invalid JSON: %s" % exc)
if any(character not in " \t\r\n" for character in text[end:]):
    reject("contains trailing content or non-RFC-8259 whitespace")
if not isinstance(value, dict):
    reject("does not contain a structured candidate")
if "attempt_id" in value:
    candidate = raw
elif isinstance(value.get("structured_output"), dict):
    candidate = json.dumps(value["structured_output"], ensure_ascii=False,
                           separators=(",", ":")).encode("utf-8")
elif isinstance(value.get("result"), dict):
    candidate = json.dumps(value["result"], ensure_ascii=False,
                           separators=(",", ":")).encode("utf-8")
elif isinstance(value.get("result"), str):
    candidate = value["result"].encode("utf-8")
else:
    reject("does not contain a structured candidate")
try:
    with open(destination, "wb") as handle:
        handle.write(candidate)
except OSError as exc:
    reject("cannot retain candidate: %s" % exc)
PY
  }

  validate_codex_snapshot() {
    snapshot_root="$1"
    snapshot_out="$2"
    python3 - "$snapshot_root" "$packet_state_before" "$snapshot_out" <<'PY' || exit 1
import hashlib
import json
import os
import stat
import sys

root, state_path, out_path = sys.argv[1:]

def reject(message):
    raise SystemExit("run-cold-reviewer: readiness Codex snapshot " + message)

def sha_file(path):
    parent = os.path.dirname(path)
    try:
        parent_before = os.lstat(parent)
        path_before = os.lstat(path)
        flags = (os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) |
                 getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_CLOEXEC", 0))
        descriptor = os.open(path, flags)
    except OSError as exc:
        reject("cannot securely hash snapshot member %s: %s" % (path, exc))
    digest = hashlib.sha256()
    size = 0
    try:
        opened_before = os.fstat(descriptor)
        if (stat.S_ISLNK(path_before.st_mode) or not stat.S_ISREG(path_before.st_mode) or
                path_before.st_nlink != 1 or not stat.S_ISREG(opened_before.st_mode) or
                opened_before.st_nlink != 1 or
                (path_before.st_dev, path_before.st_ino) !=
                (opened_before.st_dev, opened_before.st_ino)):
            reject("snapshot hash target is not one exact unaliased regular file")
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
            size += len(chunk)
        opened_after = os.fstat(descriptor)
    finally:
        os.close(descriptor)
    try:
        path_after = os.lstat(path)
        parent_after = os.lstat(parent)
    except OSError as exc:
        reject("snapshot hash binding disappeared: %s" % exc)
    identity = (opened_before.st_dev, opened_before.st_ino)
    if ((opened_after.st_dev, opened_after.st_ino) != identity or
            opened_after.st_nlink != 1 or opened_after.st_size != size or
            (path_after.st_dev, path_after.st_ino) != identity or path_after.st_nlink != 1 or
            not stat.S_ISREG(path_after.st_mode) or stat.S_ISLNK(parent_before.st_mode) or
            not stat.S_ISDIR(parent_before.st_mode) or
            (parent_after.st_dev, parent_after.st_ino) !=
            (parent_before.st_dev, parent_before.st_ino)):
        reject("snapshot hash identity, bytes, link count, or parent changed")
    return digest.hexdigest()

def pairs_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            reject("retained binding state contains duplicate JSON key: " + key)
        result[key] = value
    return result

try:
    root_mode = os.lstat(root).st_mode
    raw = open(state_path, "rb").read()
except OSError as exc:
    reject("cannot read retained binding state: %s" % exc)
if raw.startswith(b"\xef\xbb\xbf"):
    reject("retained binding state contains a byte order mark")
try:
    text = raw.decode("utf-8")
    decoder = json.JSONDecoder(
        object_pairs_hook=pairs_object,
        parse_constant=lambda value: reject("retained binding state contains non-RFC-8259 constant: " + value),
    )
    start = 0
    while start < len(text) and text[start] in " \t\r\n":
        start += 1
    state, end = decoder.raw_decode(text, start)
except (UnicodeDecodeError, ValueError, json.JSONDecodeError) as exc:
    reject("retained binding state is invalid JSON: %s" % exc)
if any(character not in " \t\r\n" for character in text[end:]):
    reject("retained binding state has trailing content or non-RFC-8259 whitespace")
if stat.S_ISLNK(root_mode) or not stat.S_ISDIR(root_mode):
    reject("root is a symlink or not a directory")
root_info = os.lstat(root)
root_identity = (root_info.st_dev, root_info.st_ino)
expected = {item["path"]: item["sha256"] for item in state["allowlist"]}
packet_path = os.path.join(root, "packet.json")
try:
    packet_mode = os.lstat(packet_path).st_mode
except OSError as exc:
    reject("packet.json is missing: %s" % exc)
packet_info = os.lstat(packet_path)
if stat.S_ISLNK(packet_mode) or not stat.S_ISREG(packet_mode) or packet_info.st_nlink != 1:
    reject("packet.json is a symlink or not a regular file")
if sha_file(packet_path) != state["manifest_sha256"]:
    reject("packet.json bytes differ from the validated original")
actual = []
identities = {}
directory_identities = {}
for current, directories, files in os.walk(root, topdown=True, followlinks=False):
    current_info = os.lstat(current)
    if stat.S_ISLNK(current_info.st_mode) or not stat.S_ISDIR(current_info.st_mode):
        reject("contains a symlink or special directory")
    current_identity = (current_info.st_dev, current_info.st_ino)
    if current_identity in directory_identities:
        reject("contains a directory identity alias")
    directory_identities[current_identity] = current
    for name in directories:
        member = os.path.join(current, name)
        mode = os.lstat(member).st_mode
        if stat.S_ISLNK(mode) or not stat.S_ISDIR(mode):
            reject("contains a symlink or special directory")
    for name in files:
        member = os.path.join(current, name)
        info = os.lstat(member)
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
            reject("contains a symlink or special file")
        relative = os.path.relpath(member, root)
        try:
            relative.encode("ascii")
        except UnicodeEncodeError:
            reject("contains a non-ASCII path")
        actual.append(relative)
        identity = (info.st_dev, info.st_ino)
        if identity in identities or info.st_nlink != 1:
            reject("contains a hard-link or file-identity alias")
        identities[identity] = relative
for identity, directory in directory_identities.items():
    current_info = os.lstat(directory)
    if stat.S_ISLNK(current_info.st_mode) or (current_info.st_dev, current_info.st_ino) != identity:
        reject("directory identity changed during snapshot enumeration")
current_root_info = os.lstat(root)
if (current_root_info.st_dev, current_root_info.st_ino) != root_identity:
    reject("root identity changed during snapshot validation")
if set(actual) != {"packet.json"} | set(expected):
    reject("file set is not exact packet.json plus allowlist")
observed = []
for relative in sorted(expected, key=lambda item: item.encode("ascii")):
    path = os.path.join(root, *relative.split("/"))
    if sha_file(path) != expected[relative]:
        reject("payload hash mismatch: " + relative)
    observed.append({"path": relative, "sha256": expected[relative]})
for identity, directory in directory_identities.items():
    current_info = os.lstat(directory)
    if stat.S_ISLNK(current_info.st_mode) or (current_info.st_dev, current_info.st_ino) != identity:
        reject("directory identity changed before snapshot validation completed")
current_root_info = os.lstat(root)
if (current_root_info.st_dev, current_root_info.st_ino) != root_identity:
    reject("root identity changed before snapshot validation completed")
with open(out_path, "w", encoding="utf-8") as handle:
    json.dump({"allowlist": observed, "manifest_sha256": state["manifest_sha256"]}, handle,
              ensure_ascii=True, separators=(",", ":"), sort_keys=True)
    handle.write("\n")
PY
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
    snapshot_state_before="$readiness_tmp/codex-snapshot-before.json"
    snapshot_state_after="$readiness_tmp/codex-snapshot-after.json"
    validate_codex_snapshot "$snap_ctx" "$snapshot_state_before"

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
    while IFS= read -r deny_location; do
      supplied_location="$(printf '%s' "$deny_location" | jq -er '.supplied')" \
        || fail "cannot read validated readiness Codex supplied deny path"
      canonical_location="$(printf '%s' "$deny_location" | jq -er '.canonical')" \
        || fail "cannot read validated readiness Codex canonical deny path"
      append_readiness_deny "$supplied_location"
      append_readiness_deny "$canonical_location"
    done < "$codex_deny_locations"
    # These default stores are already physically covered by the mandatory HOME
    # deny. Retain their explicit spellings for diagnostics and policy clarity.
    append_readiness_deny "${HOME}/.codex"
    append_readiness_deny "${HOME}/.claude"
    append_readiness_deny "${HOME}/.novadiem"

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
    validate_codex_snapshot "$snap_ctx" "$snapshot_state_after"
    cmp -s "$snapshot_state_before" "$snapshot_state_after" \
      || fail "readiness Codex snapshot changed during provider invocation"
    [ -s "$last_message" ] || fail "Codex readiness reviewer returned no final candidate"
    cp "$last_message" "$provider_candidate" || fail "cannot retain Codex readiness candidate"
  fi

  validate_readiness_packet "$packet_state_after" after || exit 1
  cmp -s "$packet_state_before" "$packet_state_after" \
    || fail "readiness packet or authoritative binding changed during provider invocation"
  custody_command check-empty || exit 1
  [ ! -e "$canonical_verdict" ] && [ ! -L "$canonical_verdict" ] \
    || fail "canonical readiness verdict collided after provider invocation"
  custody_command check-empty || exit 1

  candidate_bytes="$readiness_tmp/validated-candidate.json"
  python3 - "$provider_candidate" "$candidate_bytes" <<'PY' || exit 1
import json
import sys

source_path, candidate_out = sys.argv[1:]

def reject(message):
    raise SystemExit("run-cold-reviewer: readiness candidate " + message)

def pairs_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            reject("contains duplicate JSON key: " + key)
        result[key] = value
    return result

try:
    raw = open(source_path, "rb").read()
except OSError as exc:
    reject("cannot be read: %s" % exc)
if raw.startswith(b"\xef\xbb\xbf"):
    reject("contains a byte order mark")
try:
    text = raw.decode("utf-8")
    decoder = json.JSONDecoder(
        object_pairs_hook=pairs_object,
        parse_constant=lambda value: reject("contains non-RFC-8259 constant: " + value),
    )
    start = 0
    while start < len(text) and text[start] in " \t\r\n":
        start += 1
    candidate, end = decoder.raw_decode(text, start)
except (UnicodeDecodeError, ValueError, json.JSONDecodeError) as exc:
    reject("is invalid JSON: %s" % exc)
if any(character not in " \t\r\n" for character in text[end:]):
    reject("contains trailing content or non-RFC-8259 whitespace")
expected = {"attempt_id", "review_mode", "reviewed_artifacts", "blocker_ids", "blockers", "warnings"}
if not isinstance(candidate, dict) or set(candidate) != expected:
    reject("object has the wrong exact six-field key set")
try:
    with open(candidate_out, "wb") as handle:
        handle.write(raw)
except OSError as exc:
    reject("cannot stage validated provider bytes: %s" % exc)
PY

  publish_no_clobber() {
    source_path="$1"
    target_path="$2"
    identity_key="$3"
    retained_fd="${4:-}"
    python3 - "$source_path" "$target_path" "$publication_identities" "$identity_key" \
      "$retained_fd" <<'PY'
import json
import os
import re
import secrets
import stat
import sys

source, target, identity_path, identity_key, retained_fd = sys.argv[1:]
parent = os.path.dirname(target)
name = os.path.basename(target)
if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", name):
    raise SystemExit("run-cold-reviewer: no-clobber publication basename is unsafe")
def identity_pairs(items):
    result = {}
    for key, value in items:
        if key in result:
            raise ValueError("duplicate identity key")
        result[key] = value
    return result

try:
    raw_identity = open(identity_path, "rb").read()
    text_identity = raw_identity.decode("utf-8")
    decoder = json.JSONDecoder(object_pairs_hook=identity_pairs,
                               parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))
    identity_start = 0
    while identity_start < len(text_identity) and text_identity[identity_start] in " \t\r\n":
        identity_start += 1
    identities, identity_end = decoder.raw_decode(text_identity, identity_start)
    if any(character not in " \t\r\n" for character in text_identity[identity_end:]):
        raise ValueError("trailing identity content")
    expected = identities[identity_key]
except (OSError, UnicodeDecodeError, ValueError, KeyError, TypeError) as exc:
    raise SystemExit("run-cold-reviewer: cannot load publication parent identity: %s" % exc)
if expected.get("path") != parent or type(expected.get("dev")) is not int or type(expected.get("ino")) is not int:
    raise SystemExit("run-cold-reviewer: publication target does not bind the recorded parent")
expected_identity = (expected["dev"], expected["ino"])

def verify_parent_path():
    try:
        info = os.lstat(parent)
    except OSError as exc:
        raise SystemExit("run-cold-reviewer: publication parent path is unavailable: %s" % exc)
    if (stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode) or
            (info.st_dev, info.st_ino) != expected_identity):
        raise SystemExit("run-cold-reviewer: publication parent path identity changed")

verify_parent_path()
directory_flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
try:
    directory = os.dup(int(retained_fd)) if retained_fd else os.open(parent, directory_flags)
except OSError as exc:
    raise SystemExit("run-cold-reviewer: cannot open anchored publication parent: %s" % exc)
temporary = ".readiness-publish-%s.tmp" % secrets.token_hex(12)
linked = False
try:
    directory_info = os.fstat(directory)
    if not stat.S_ISDIR(directory_info.st_mode) or (directory_info.st_dev, directory_info.st_ino) != expected_identity:
        raise SystemExit("run-cold-reviewer: anchored publication parent identity mismatch")
    verify_parent_path()
    for existing in os.listdir(directory):
        if existing == name or existing.lower() == name.lower():
            raise SystemExit("run-cold-reviewer: no-clobber publication collision: " + target)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    descriptor = os.open(temporary, flags, 0o600, dir_fd=directory)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            with open(source, "rb") as source_handle:
                handle.write(source_handle.read())
            handle.flush()
            os.fsync(handle.fileno())
        verify_parent_path()
        os.link(temporary, name, src_dir_fd=directory, dst_dir_fd=directory,
                follow_symlinks=False)
        linked = True
        os.fsync(directory)
        verify_parent_path()
    finally:
        try:
            os.unlink(temporary, dir_fd=directory)
        except FileNotFoundError:
            pass
finally:
    os.close(directory)
PY
  }

  candidate_binding="$readiness_tmp/published-candidate-binding.json"
  validate_published_candidate() {
    expected_source="$1"
    binding_mode="$2"
    reopened_output="$3"
    python3 - "$result_dir" "$publication_identities" 8 "${output_id}.json" \
      "$expected_source" "$candidate_binding" "$binding_mode" "$reopened_output" <<'PY' || exit 1
import hashlib
import json
import os
import stat
import sys

(parent_path, identity_path, descriptor_text, candidate_name, expected_source,
 binding_path, binding_mode, reopened_output) = sys.argv[1:]

def reject(message):
    raise SystemExit("run-cold-reviewer: published readiness candidate " + message)

def pairs(items):
    result = {}
    for key, value in items:
        if key in result:
            reject("binding state contains a duplicate JSON key: " + key)
        result[key] = value
    return result

def load_private_json(path):
    try:
        raw = open(path, "rb").read()
        text = raw.decode("utf-8")
        decoder = json.JSONDecoder(
            object_pairs_hook=pairs,
            parse_constant=lambda value: reject("binding state contains an invalid constant"),
        )
        start = 0
        while start < len(text) and text[start] in " \t\r\n":
            start += 1
        value, end = decoder.raw_decode(text, start)
    except (OSError, UnicodeDecodeError, ValueError, json.JSONDecodeError) as exc:
        reject("binding state cannot be loaded: %s" % exc)
    if any(character not in " \t\r\n" for character in text[end:]):
        reject("binding state has trailing content")
    return value

try:
    descriptor = int(descriptor_text)
    identities = load_private_json(identity_path)
    expected_parent = identities["candidate"]
    parent_info = os.fstat(descriptor)
    path_info = os.lstat(parent_path)
except (OSError, ValueError, KeyError, TypeError) as exc:
    reject("cannot validate retained result parent: %s" % exc)
parent_identity = (expected_parent.get("dev"), expected_parent.get("ino"))
if (expected_parent.get("path") != parent_path or type(parent_identity[0]) is not int or
        type(parent_identity[1]) is not int or not stat.S_ISDIR(parent_info.st_mode) or
        stat.S_ISLNK(path_info.st_mode) or not stat.S_ISDIR(path_info.st_mode) or
        (parent_info.st_dev, parent_info.st_ino) != parent_identity or
        (path_info.st_dev, path_info.st_ino) != parent_identity):
    reject("retained result parent identity changed")
if os.listdir(descriptor) != [candidate_name]:
    reject("result directory does not contain exactly the bound candidate")

flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0)
try:
    candidate_fd = os.open(candidate_name, flags, dir_fd=descriptor)
except OSError as exc:
    reject("cannot reopen through retained result descriptor: %s" % exc)
try:
    before = os.fstat(candidate_fd)
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
        reject("is not one unaliased regular file")
    chunks = []
    while True:
        chunk = os.read(candidate_fd, 1024 * 1024)
        if not chunk:
            break
        chunks.append(chunk)
    raw = b"".join(chunks)
    after = os.fstat(candidate_fd)
finally:
    os.close(candidate_fd)
if ((before.st_dev, before.st_ino, before.st_size, before.st_nlink) !=
        (after.st_dev, after.st_ino, after.st_size, after.st_nlink) or
        after.st_nlink != 1 or after.st_size != len(raw)):
    reject("identity or bytes changed while reopened")
try:
    linked = os.stat(candidate_name, dir_fd=descriptor, follow_symlinks=False)
    canonical_member = os.lstat(os.path.join(parent_path, candidate_name))
    final_parent = os.lstat(parent_path)
except OSError as exc:
    reject("path binding changed while reopened: %s" % exc)
candidate_identity = (after.st_dev, after.st_ino)
if (not stat.S_ISREG(linked.st_mode) or linked.st_nlink != 1 or
        (linked.st_dev, linked.st_ino) != candidate_identity or
        not stat.S_ISREG(canonical_member.st_mode) or canonical_member.st_nlink != 1 or
        (canonical_member.st_dev, canonical_member.st_ino) != candidate_identity):
    reject("directory member was unlinked, replaced, or hard-linked")
if (stat.S_ISLNK(final_parent.st_mode) or not stat.S_ISDIR(final_parent.st_mode) or
        (final_parent.st_dev, final_parent.st_ino) != parent_identity):
    reject("result parent path changed while candidate was reopened")

digest = hashlib.sha256(raw).hexdigest()
observed = {
    "dev": after.st_dev,
    "ino": after.st_ino,
    "name": candidate_name,
    "parent_dev": parent_identity[0],
    "parent_ino": parent_identity[1],
    "sha256": digest,
    "size": len(raw),
}
if binding_mode == "initial":
    try:
        expected_raw = open(expected_source, "rb").read()
    except OSError as exc:
        reject("cannot read validated provider bytes: %s" % exc)
    if raw != expected_raw or digest != hashlib.sha256(expected_raw).hexdigest():
        reject("published raw bytes differ from validated provider bytes")
    try:
        with open(binding_path, "x", encoding="utf-8") as handle:
            json.dump(observed, handle, ensure_ascii=True, separators=(",", ":"), sort_keys=True)
            handle.write("\n")
    except OSError as exc:
        reject("cannot retain immutable candidate binding: %s" % exc)
elif binding_mode == "final":
    expected_binding = load_private_json(binding_path)
    if expected_binding != observed:
        reject("identity, link count, size, or SHA-256 changed after initial reopen")
else:
    reject("has an invalid internal validation mode")
try:
    with open(reopened_output, "wb") as handle:
        handle.write(raw)
except OSError as exc:
    reject("cannot retain reopened raw bytes: %s" % exc)
PY
  }

  candidate_path="$result_dir/${output_id}.json"
  reopened_candidate="$readiness_tmp/reopened-candidate.json"
  custody_command publish-candidate "$candidate_bytes" "${output_id}.json" "$reopened_candidate" || exit 1
  rm -f "$candidate_bytes" || fail "cannot discard private pre-publication candidate bytes"
  derivation_candidate="$readiness_tmp/derivation-candidate.json"
  custody_command validate-candidate "$derivation_candidate" || exit 1
  cmp -s "$reopened_candidate" "$derivation_candidate" \
    || fail "published readiness candidate bytes changed before canonical derivation"

  canonical_bytes="$readiness_tmp/canonical-verdict.json"
  python3 - "$derivation_candidate" "$packet_state_before" "$readiness_schema" \
    "$canonical_bytes" <<'PY' || exit 1
import datetime
import json
import re
import sys
import unicodedata

candidate_path, state_path, schema_path, canonical_out = sys.argv[1:]

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
    try:
        raw = open(path, "rb").read()
    except OSError as exc:
        reject("cannot read published or binding input %s: %s" % (path, exc))
    if raw.startswith(b"\xef\xbb\xbf"):
        reject("contains a byte order mark")
    try:
        text = raw.decode("utf-8")
        decoder = json.JSONDecoder(
            object_pairs_hook=pairs_object,
            parse_constant=lambda value: reject("contains non-RFC-8259 constant: " + value),
        )
        start = 0
        while start < len(text) and text[start] in " \t\r\n":
            start += 1
        value, end = decoder.raw_decode(text, start)
    except (UnicodeDecodeError, ValueError, json.JSONDecodeError) as exc:
        reject("is invalid JSON: %s" % exc)
    if any(character not in " \t\r\n" for character in text[end:]):
        reject("contains trailing content or non-RFC-8259 whitespace")
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

try:
    candidate_text = candidate_raw.decode("utf-8")
    decoder = json.JSONDecoder(object_pairs_hook=pairs_object)
    candidate_start = 0
    while candidate_start < len(candidate_text) and candidate_text[candidate_start] in " \t\r\n":
        candidate_start += 1
    unused_candidate, candidate_end = decoder.raw_decode(candidate_text, candidate_start)
    if candidate_end <= candidate_start or candidate_text[candidate_end - 1] != "}":
        reject("published candidate does not end in one JSON object")
    adapter_suffix = (
        ',"verdict":' + json.dumps(verdict, ensure_ascii=True, separators=(",", ":")) +
        ',"timestamp":' + json.dumps(canonical["timestamp"], ensure_ascii=True, separators=(",", ":")) +
        '}'
    )
    canonical_raw = (candidate_text[:candidate_end - 1] + adapter_suffix +
                     candidate_text[candidate_end:]).encode("utf-8")
    with open(canonical_out, "wb") as handle:
        handle.write(canonical_raw)
except (OSError, UnicodeDecodeError, ValueError, json.JSONDecodeError) as exc:
    reject("cannot stage canonical verdict bytes: %s" % exc)
PY
  validate_readiness_packet "$packet_state_final" final || exit 1
  cmp -s "$packet_state_before" "$packet_state_final" \
    || fail "readiness packet or authoritative binding changed before canonical publication"
  final_reopened_candidate="$readiness_tmp/final-reopened-candidate.json"
  custody_command validate-candidate "$final_reopened_candidate" || exit 1
  cmp -s "$reopened_candidate" "$final_reopened_candidate" \
    || fail "published readiness candidate bytes changed before canonical publication"
  [ ! -e "$canonical_verdict" ] && [ ! -L "$canonical_verdict" ] \
    || fail "canonical readiness verdict collided before publication"
  custody_command publish-verdict "$canonical_bytes" "${attempt_id}.json" || exit 1
  readiness_metadata="$readiness_tmp/readiness-metadata.json"
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
    }' > "$readiness_metadata" || fail "cannot stage readiness result metadata"
  custody_command finalize || exit 1
  wait "$custody_pid" || fail "readiness custody helper did not exit cleanly"
  custody_pid=""
  cat "$readiness_metadata"
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
