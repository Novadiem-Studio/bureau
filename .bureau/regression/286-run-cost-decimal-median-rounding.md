name: run-cost-decimal-median-rounding (currency median uses Decimal half-even cents with null propagation)
phase: bug-fix · 20260908-run-cost-median-rounding
owner: scripts/run-cost-dataset.py (complete-essay cost median rounding only)
command: |
  set -eu
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT HUP INT TERM
  python3 - "$ROOT" "$TMP" <<'PY'
  import json
  import pathlib
  import subprocess
  import sys

  root = pathlib.Path(sys.argv[1])
  tmp = pathlib.Path(sys.argv[2])
  script = root / "scripts" / "run-cost-dataset.py"

  def price(rate):
      return {
          "model": f"fixture-{rate}",
          "input": rate,
          "cache_write": 0,
          "cache_read": 0,
          "output": 0,
          "source": "fixture",
          "fetched": "2026-09-08",
      }

  pricing = {
      "models": {
          "cost-7.11": price(7.11),
          "cost-12.26": price(12.26),
          "cost-12.27": price(12.27),
          "cost-24.63": price(24.63),
          "cost-24.64": price(24.64),
          "zero": price(0),
      },
      "openrouter": {
          "x-ai/grok-4.3": {
              "input": 0,
              "output": 0,
              "source": "fixture",
              "fetched": "2026-09-08",
          }
      },
      "grok_bytes_per_token_estimate": 4,
  }
  pricing_path = tmp / "pricing.json"
  pricing_path.write_text(json.dumps(pricing))

  def add_run(repo, ordinal, model):
      slug = f"202609{ordinal:02d}-{model}"
      run_dir = repo / ".bureau" / "runs" / slug
      run_dir.mkdir(parents=True)
      accounting = {
          "schema_version": 2,
          "run": {
              "workflow": {"value": "write-article"},
              "run_date": {"value": f"2026-09-{ordinal:02d}"},
          },
          "conductor_tokens": {
              "confidence": "exact",
              "tokens": {
                  "input": {"value": 1000000},
                  "cache_creation": {"value": 0},
                  "cache_read": {"value": 0},
                  "output": {"value": 0},
              },
          },
          "specialist_spawns": [
              {
                  "agent": {"value": "The Systemsmith"},
                  "actual_model": {"value": "zero"},
                  "tokens": {
                      "input": {"value": 0},
                      "cache_creation": {"value": 0},
                      "cache_read": {"value": 0},
                      "output": {"value": 0},
                  },
              }
          ],
      }
      (run_dir / "accounting.json").write_text(json.dumps(accounting))
      (run_dir / "model-routing.json").write_text(
          json.dumps({"roles": {"conductor": {"model": model}}})
      )
      (run_dir / "article.mdx").write_text(f'---\nslug: "{slug}"\n---\n')

  def run_case(name, models):
      repo = tmp / name / "repo"
      out = tmp / name / "out"
      repo.mkdir(parents=True)
      for ordinal, model in enumerate(models, 1):
          add_run(repo, ordinal, model)
      subprocess.run(
          [
              sys.executable,
              str(script),
              "--target-repo",
              str(repo),
              "--pricing",
              str(pricing_path),
              "--out",
              str(out),
              "--as-of",
              "2026-09-08",
          ],
          check=True,
          stdout=subprocess.DEVNULL,
      )
      return json.loads((out / "dataset.json").read_text())

  up_tie = run_case("up-tie", ["cost-12.27", "cost-24.64"])
  assert [run["totals"]["total_usd_equiv"] for run in up_tie["runs"]] == [12.27, 24.64]
  assert up_tie["rollup"]["median_usd_equiv_per_essay"] == 18.46, up_tie["rollup"]

  down_tie = run_case("down-tie", ["cost-12.26", "cost-24.63"])
  assert down_tie["rollup"]["median_usd_equiv_per_essay"] == 18.44, down_tie["rollup"]

  odd = run_case("odd", ["cost-7.11", "cost-12.27", "cost-24.64"])
  assert odd["rollup"]["median_usd_equiv_per_essay"] == 12.27, odd["rollup"]

  unavailable = run_case("unavailable", ["cost-12.27", "unpriced"])
  assert unavailable["rollup"]["complete_essay_runs"] == 2, unavailable["rollup"]
  assert unavailable["rollup"]["median_usd_equiv_per_essay"] is None, unavailable["rollup"]

  empty = run_case("empty", [])
  assert empty["rollup"] == {}, empty["rollup"]
  print("PASS")
  PY
expected: PASS
