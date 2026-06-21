# `.bureau/regression/` — this repo's standing Bureau regression suite

Committed regression fixtures that guard the framework's own mechanical guarantees, so a
later edit to a shipped script can't silently break one. This is the **promoted** home for
fixtures that began life as per-run artifacts under `output/runs/<slug>/regression/`.

## Run it

```sh
sh .bureau/regression/run.sh
```

The runner resolves the repo root, exports `$ROOT`, and runs every `NN-*.md` fixture.
**A fixture passes when its `command` exits 0.** Each fixture is authored so that its
guarantee holding ⇒ exit 0, and is *mutation-tested* — deleting the guaranteed line from the
script makes the fixture exit non-zero. `retired:`/`slow:` fixtures are skipped.

## Fixture format

Each `NN-<slug>.md` follows `docs/conventions.md § Regression fixture file format`
(`name` / `command` / `expected` / `phase` / `owner`). Paths are repo-relative: every
command resolves `ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"` and references
`"$ROOT/scripts/…"`, so the suite runs on any checkout (not one machine's absolute paths).

## What's covered (Bundle 09 — The Delegate)

15 fixtures: the load-bearing isolation/safety guarantees of the delegate bridge —
hash-binding (EC2), missing-field rejection (EC10), the revise-count cap vs. attempt (EC7),
the `mkdir` lock + dead-PID reclaim (EC3), skip-existing-verdict (FR38), await-verdict timeout
(FR37), `.tmp`-not-verdict (EC6), notify fallback (EC4), the spawn-invocation identity/isolation
guard (EC1/EC8), no-preference-modeling (FR44), and launcher robustness — plus the model-policy
role and verdict-schema contracts.

## Lifecycle

The scratch → promote → standing lifecycle is now canonical. During an execute-plan build,
fixtures are authored in `RUN_DIR/regression/` (gitignored). At close-out, the Conductor
promotes selected fixtures here via `scripts/promote-fixtures.sh`, commits them on the
integration branch, and verifies the suite is green. On the next run, `workflows/execute-plan.md`
step 6 shells this `run.sh` as part of its prior-fixture re-run gate.

Full lifecycle definition: `docs/conventions.md § Regression fixture file format`.
Promotion script contract: `scripts/README.md § promote-fixtures.sh`.
Wiring into execute-plan close-out: `workflows/execute-plan.md § step 7`.
