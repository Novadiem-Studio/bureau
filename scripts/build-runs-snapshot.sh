#!/usr/bin/env bash
# Build a derived rollup of per-run index entries into runs-snapshot.json.
#
# Usage:
#   ./scripts/build-runs-snapshot.sh
#
# Reads:   output/studio/runs-index/*.json  (top-level only — archived entries excluded per W5)
# Writes:  output/studio/runs-snapshot.json (atomically)
#
# The rollup is a cache — the source of truth is `runs-index/*.json`. A consumer
# that cannot find the rollup falls back to globbing that directory.
#
# Safe to run anytime (pure derivation; a stale or missing rollup is never a
# correctness problem). Requires python3 (already a runtime dependency for JSON
# validation throughout the framework).
#
# Exit codes:
#   0  rollup written (or no entries found — empty array written)
#   1  python3 missing or write failed

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

die() { echo "build-runs-snapshot: $*" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || die "python3 required"

INDEX_DIR="$ROOT/output/studio/runs-index"
SNAPSHOT="$ROOT/output/studio/runs-snapshot.json"
TMP="$ROOT/output/studio/.runs-snapshot.json.tmp"

# Ensure index dirs exist (safe to run even on a fresh install before any run)
mkdir -p "$INDEX_DIR"
mkdir -p "$INDEX_DIR/archive"

# Glob top-level *.json only (archived entries live under runs-index/archive/ — excluded per W5)
python3 - "$INDEX_DIR" "$TMP" <<'PYEOF'
import json, sys, glob, os

index_dir = sys.argv[1]
tmp_path  = sys.argv[2]

entries = []
for path in sorted(glob.glob(os.path.join(index_dir, "*.json"))):
    try:
        with open(path) as f:
            entries.append(json.load(f))
    except Exception as e:
        print(f"build-runs-snapshot: warning: skipping {path}: {e}", file=sys.stderr)

with open(tmp_path, "w") as f:
    json.dump(entries, f, indent=2)
    f.write("\n")
PYEOF

mv "$TMP" "$SNAPSHOT"
count=$(python3 -c "import json; print(len(json.load(open('$SNAPSHOT'))))")
echo "build-runs-snapshot: wrote $SNAPSHOT ($count entries)"
