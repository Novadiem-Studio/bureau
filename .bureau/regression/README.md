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

## Status (prototype)

This directory is a **prototype** of the "fixtures graduate from run-artifact to committed
canon" pattern. The full lifecycle — auto-promote on execute-plan close-out, and have a future
run's re-run gate read this dir as its baseline — is not yet wired into `workflows/execute-plan.md`
or `docs/conventions.md`. That formalization is a pending bundle. For now, run it by hand or from
a pre-push / CI hook.

Provenance: copied from `output/runs/20260620-principal-delegate/regression/`, repointed to
repo-relative paths.
