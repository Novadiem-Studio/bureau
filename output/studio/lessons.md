# Cross-run learning log

This file is the framework's cross-run learning log. The Conductor appends one entry per
failure repair — gated by the `lessons-append` gate in both `workflows/operational-build.md`
and `workflows/execute-plan.md`, each in its respective close-out step. The full entry format
is defined below.

A run that produced no failure repair appends nothing. A run that produced multiple failure
repairs appends one entry per repair — multiple entries may share the same `run:` value. The
recurrence rule (per `docs/conventions.md § Recurrence rule`) counts **distinct `run:` values**
among entries sharing a failure tail, not the total number of entries — two entries from the
same run are still one run, not two, for recurrence-counting purposes.

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

<!-- Live lessons log — append entries below; one per failure repair (one per failure-signature: slug). -->

run: 20260620-principal-delegate
failure-signature: 12-fixture-false-pass-on-comment-match
artifact-patched: output/runs/20260620-principal-delegate/regression/{04,09,12,15}-*.md (strip comment lines before grepping; mutation-test each static guard)
status: promoted — comment-strip authoring rule added to docs/conventions.md § Regression fixture file format
note: A static-grep fixture false-passes when its asserted token also appears in a code COMMENT — the guarantee can be deleted from the real code and the fixture still passes. Caught by the Challenger via mutation testing (delete the guaranteed line from a script copy → the fixture must FAIL). Rule: grep only NON-comment code (e.g. pipe through `grep -v '^[[:space:]]*#'`), and always mutation-test a static guard before trusting it.

run: 20260620-principal-delegate
failure-signature: 12-bsd-grep-mid-dollar-mismatch
artifact-patched: output/runs/20260620-principal-delegate/regression/{05,09,12}-*.md (use grep -F for literal-$ patterns)
status: promoted — BSD grep / literal-$ rule added to docs/conventions.md § Regression fixture file format
note: macOS/BSD grep BRE/ERE mishandles a `$` in the MIDDLE of a pattern, so `grep 'add-dir "$CTX"'` fails to match the literal text while `grep -F` matches it. Use grep -F (fixed-string) for any fixture/guard pattern containing a literal `$`. Confirmed twice this run.
