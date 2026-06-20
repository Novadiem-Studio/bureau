# Cross-run learning log

This file is the framework's cross-run learning log. The Conductor appends one entry after
each run that produced a failure repair — gated by the `lessons-append` gate in both
`workflows/operational-build.md` and `workflows/execute-plan.md`, each in its respective
close-out step. The full entry format is defined below.

A run that produced no failure repair appends nothing. One entry per run that did.

## Entry format

Every entry has four fields:

| Field | Value shape |
|-------|-------------|
| `run:` | The RUN_DIR slug (the `<yyyymmdd>-<task-slug>` dir name). This is the **recurrence-count key**: the recurrence rule (`docs/conventions.md § Recurrence rule`) counts **distinct `run:` values** for a given failure tail, not occurrences. Two failure signatures recorded in the same run count as one run, not two. |
| `failure-signature:` | The failure-signature slug from `docs/conventions.md § Failure signature format` (`<run-slug>-<NN>-<layer>-<short-description>`), OR a one-line summary if no formal slug was recorded for the failure. |
| `artifact-patched:` | The durable framework file that was changed to repair the failure, OR `none — deferred` when no durable file was patched this run. |
| `status:` | Exactly one of the valid values below. |

### Valid `status:` values

- **`promoted`** — A named change is already present in a canonical framework file (a
  convention, runbook, script, workflow, or persona). The lesson is closed.
- **`deferred: <reason>`** — Promotion is intentionally withheld. The reason line carries
  why, and a next-review trigger (a run or a date). Per `docs/conventions.md § Recurrence
  rule`, a lesson whose failure tail now appears in two distinct `run:` values (count ≥ 2)
  must be `promoted` or carry a written `deferred: <reason>` — a blank or `scoped-local`
  entry at count ≥ 2 becomes a **Blocker** at that second (or later) run's close-out.
- **`scoped-local: <reason>`** — Judged not a framework defect (e.g. a one-off
  `env/preflight` environment glitch). **Disallowed once the same failure tail has appeared
  in two distinct `run:` values** — at count ≥ 2 the failure is evidence of a recurring
  issue, not a one-off, so `scoped-local` is no longer a legal status for it.

### Format example

```
format example — NOT a real lesson, remove before use

run: EXAMPLE
failure-signature: EXAMPLE-01-example-synthetic-not-real
artifact-patched: docs/runbooks/ios-build.md
status: promoted
```

`run: EXAMPLE` is a synthetic slug, not a real `<run-slug>`, and `example-synthetic-not-real`
is a tail no real failure can produce — so the recurrence rule never matches this entry and it
is never counted as a real lesson or a recurrence.

---

<!-- Live lessons log — append entries below; one per run that produced a failure repair. -->
