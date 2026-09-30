# Sharding a target project's CI

Build runs lean on CI now. A routine integration checkpoint reads `gh pr checks` on the pushed
commit instead of running the full suite locally, and the Conductor reads CI before each coder
dispatch (`docs/conductor-gates.md § Integration checkpoint cadence (build runs)`). That only
saves time if CI is fast. A suite that runs as one CI job of 20-40 minutes puts the wait back.

This is the recipe rheo-stream used (rheos/rheostream#253, issue #252). Its Python suite, about
3,500 tests, ran as a single job in about 36 minutes. Split five ways, the slowest shard took
4m58s. The recipe is for pytest; the four rules carry over to any runner.

## 1. A plugin loaded only in CI, never a root conftest

Put the shard logic in a pytest plugin module (rheo-stream: `scripts/ci_pytest_shard.py`) and load
it on the CI command line only:

```yaml
- name: Pytest
  env:
    RHEO_TEST_SHARD: ${{ matrix.shard }}/5
    PYTHONPATH: scripts
  run: uv run pytest -p ci_pytest_shard
```

Two reasons it is not a root `conftest.py`. A root conftest shadows any `from conftest import ...`
the suite already uses. And a plugin named with `-p` is not inherited by pytest subprocesses the
suite starts itself (rheo-stream's acceptance-matrix `--collect-only` and its fail-fast probe),
which must keep seeing the whole suite even inside a shard job. With the variable unset the
plugin does nothing, so `make test` on a laptop is unchanged.

## 2. Whole files per shard, weighted

The plugin hooks `pytest_collection_modifyitems`, computes a partition of the collected node ids,
keeps its own shard's items and reports the rest through `pytest_deselected`.

- **Whole files go to one shard.** A module-scoped fixture is then built once, in one job.
- **Weight each file.** Weight is the file's test count, times a factor for expensive tests.
  rheo-stream weights files under `postgres/` 5x, because each of those tests provisions a
  database and they dominate the run.
- **Greedy and deterministic.** Sort files heaviest first, ties broken on path, and give each to
  the currently lightest shard. Every job computes the same partition from the same collection,
  with no coordination between jobs.
- **Parse `i/N` strictly** and raise a usage error for anything else, so a typo cannot silently
  run nothing.

## 3. An aggregator job keeps the required check name

Branch protection names the check it waits for. Keep that name on a small job that needs
every shard (and any sibling job it replaced) and fails unless all of them succeeded:

```yaml
python:
  name: Python checks          # the required status check, unchanged
  needs: [python-static, python-tests, python-criterion-31]
  if: always()                 # a failed shard must fail this job, not skip it
  runs-on: ubuntu-latest
  steps:
    - env:
        RESULTS: ${{ join(needs.*.result, ' ') }}
      run: |
        for r in $RESULTS; do
          [ "$r" = "success" ] || { echo "::error::a Python job ended $r"; exit 1; }
        done
```

Without `if: always()`, a failed shard leaves the aggregator skipped, and a skipped required check
can read as passing. Update anything else that names the old job (acceptance matrices, tests that
parse the workflow file).

## 4. Verify exact cover

A partition that drops a file is a silent hole in CI. Prove it covers everything exactly once:

- **Unit tests on the partition function** (rheo-stream: `tests/test_shard_partition.py`): every
  file lands in exactly one shard for several N, the result does not depend on collection order,
  the weighting spreads the heavy files, and `i/N` parsing rejects bad values.
- **One real check before merging:** collect-only for each shard against the real suite and
  confirm the counts sum to the unsharded total with no node id in two shards. rheo-stream's five
  shards selected 3,523 tests, each exactly once (981, 541, 689, 660, 652).
- **The PR's own CI run** is the timing check. Record the slowest shard against the old single
  job.

Re-check the balance when the suite grows a new class of slow test; a new weight factor is
cheaper than a shard that drifts to twice the others.
