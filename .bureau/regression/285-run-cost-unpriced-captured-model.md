name: run-cost-unpriced-captured-model (exact captured tokens remain covered while unavailable USD stays null)
phase: bug-fix · 20260907-run-cost-extractor-safety-fix
owner: scripts/run-cost-dataset.py (unpriced captured model null propagation and public dataset safety)
command: |
  set -eu
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT HUP INT TERM
  mkdir -p "$TMP/repo/.bureau/runs/20260901-priced" "$TMP/repo/.bureau/runs/20260902-unpriced"
  cat > "$TMP/pricing.json" <<'JSON'
  {
    "models": {
      "opus": {
        "model": "priced-opus",
        "input": 10,
        "cache_write": 20,
        "cache_read": 1,
        "output": 30,
        "source": "fixture",
        "fetched": "2026-09-07"
      }
    },
    "openrouter": {
      "x-ai/grok-4.3": {
        "input": 1,
        "output": 2,
        "source": "fixture",
        "fetched": "2026-09-07"
      }
    },
    "grok_bytes_per_token_estimate": 4
  }
  JSON
  cat > "$TMP/repo/.bureau/runs/20260901-priced/accounting.json" <<'JSON'
  {
    "schema_version": 2,
    "run": {"workflow": {"value": "write-article"}, "run_date": {"value": "2026-09-01"}},
    "conductor_tokens": {
      "confidence": "exact",
      "tokens": {"input": {"value": 1000000}, "cache_creation": {"value": 0}, "cache_read": {"value": 0}, "output": {"value": 0}}
    },
    "specialist_spawns": [
      {
        "agent": {"value": "The Systemsmith"},
        "actual_model": {"value": "opus"},
        "tokens": {"input": {"value": 0}, "cache_creation": {"value": 0}, "cache_read": {"value": 0}, "output": {"value": 1000000}}
      }
    ]
  }
  JSON
  cat > "$TMP/repo/.bureau/runs/20260901-priced/article.mdx" <<'MDX'
  ---
  slug: "priced-control"
  ---
  MDX
  cat > "$TMP/repo/.bureau/runs/20260902-unpriced/accounting.json" <<'JSON'
  {
    "schema_version": 2,
    "run": {"workflow": {"value": "write-article"}, "run_date": {"value": "2026-09-02"}},
    "conductor_tokens": {
      "confidence": "exact",
      "tokens": {"input": {"value": 1000000}, "cache_creation": {"value": 0}, "cache_read": {"value": 0}, "output": {"value": 0}}
    },
    "specialist_spawns": [
      {
        "agent": {"value": "The Systemsmith"},
        "actual_model": {"value": "gpt-5.6-codex"},
        "tokens": {"input": {"value": 101}, "cache_creation": {"value": 102}, "cache_read": {"value": 103}, "output": {"value": 104}}
      }
    ]
  }
  JSON
  cat > "$TMP/repo/.bureau/runs/20260902-unpriced/article.mdx" <<'MDX'
  ---
  slug: "unpriced-captured"
  ---
  MDX
  python3 "$ROOT/scripts/run-cost-dataset.py" \
    --target-repo "$TMP/repo" --pricing "$TMP/pricing.json" --out "$TMP/out" \
    --as-of 2026-09-07 >/dev/null
  python3 - "$TMP/out" "$TMP/repo" <<'PY'
  import json
  import pathlib
  import sys

  out = pathlib.Path(sys.argv[1])
  target_repo = sys.argv[2]
  dataset_text = (out / "dataset.json").read_text()
  dataset = json.loads(dataset_text)
  assert "target_repo" not in dataset, dataset
  assert target_repo not in dataset_text, dataset_text

  runs = {run["run"]: run for run in dataset["runs"]}
  priced = runs["20260901-priced"]
  assert priced["coverage"] == "complete", priced
  assert priced["totals"]["claude_usd_equiv"] == 40.0, priced["totals"]
  assert priced["totals"]["total_usd_equiv"] == 40.0, priced["totals"]
  assert all(isinstance(leg["usd_equiv"], (int, float)) for leg in priced["legs"] if leg["captured"]), priced["legs"]

  unpriced = runs["20260902-unpriced"]
  unknown = next(leg for leg in unpriced["legs"] if leg["model"] == "gpt-5.6-codex")
  assert unpriced["coverage"] == "complete", unpriced
  assert unpriced["totals"]["tokens_processed_captured"] == 1000410, unpriced["totals"]
  assert unpriced["totals"]["legs_captured"] == 2, unpriced["totals"]
  assert unknown["captured"] is True, unknown
  assert unknown["confidence"] == "exact", unknown
  assert unknown["tokens"] == {"input": 101, "cache_creation": 102, "cache_read": 103, "output": 104}, unknown
  assert unknown["usd_equiv"] is None, unknown
  assert unknown["formula"] is None, unknown
  assert unpriced["totals"]["claude_usd_equiv"] is None, unpriced["totals"]
  assert unpriced["totals"]["total_usd_equiv"] is None, unpriced["totals"]

  rollup = dataset["rollup"]
  assert rollup["complete_essay_runs"] == 2, rollup
  assert rollup["median_usd_equiv_per_essay"] is None, rollup
  assert rollup["min_usd_equiv"] is None, rollup
  assert rollup["max_usd_equiv"] is None, rollup
  assert rollup["usd_equiv_by_agent_across_complete_essay_runs"]["The Systemsmith"] is None, rollup

  tables = (out / "tables.md").read_text()
  assert "| The Systemsmith | gpt-5.6-codex | 101 | 102 | 103 | 104 | n/a | n/a |" in tables, tables
  assert "| **Total** | | | | | | **n/a** | Claude n/a + Grok 0.0000 |" in tables, tables
  assert "| The Systemsmith | opus | 0 | 0 | 0 | 1,000,000 | 30.00 |" in tables, tables

  frontmatter = (out / "run-frontmatter" / "unpriced-captured.yaml").read_text()
  assert 'model: "gpt-5.6-codex", tokens: 410, cost: null' in frontmatter, frontmatter
  assert "cost: None" not in frontmatter, frontmatter

  coverage = (out / "coverage.md").read_text()
  assert "| 20260902-unpriced | v2 | complete | exact |" in coverage, coverage
  print("PASS")
  PY
expected: PASS
