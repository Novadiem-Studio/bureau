# Agent-framework ideas - execution roadmap

This folder is now organized by execution bundle, not by raw benefit rank. The original
numbered notes are preserved in [`source-notes/`](source-notes/) as source material.

The working rule: promote one bundle at a time. Each bundle should become one framework run
or one small series of runs with a clear acceptance boundary. Do not start by implementing
every source idea as a separate mechanism; several of them are the same discipline seen from
different angles.

## Recommended execution order

| Order | Bundle | Source ideas | Why here |
|---:|---|---|---|
| 1 | [Validation and safety foundation](01-validation-and-safety-foundation.md) | 13, 14, 08, 07 | Prevent wasted or unsafe execution before adding more orchestration. |
| 2 | [Reusable learning loop](02-reusable-learning-loop.md) | 01, 03, 09 | Turn real failures and repeated fixes into durable framework changes. |
| 3 | [Planning decision quality gates](03-planning-decision-quality-gates.md) | 10, 12, 02 | Improve the quality of specs and architecture choices before build work starts. |
| 4 | [Run accounting and resume signals](04-run-accounting-and-resume-signals.md) | 05, 15 | Make cost, pass count, model mix, and resume context visible after the core loop is stable. |
| 5 | [Outside cold review sidecar](05-outside-cold-review-sidecar.md) | 06 | Add optional advisory review only after artifact boundaries are clear. |
| 6 | [Navigation and runtime experiments](06-navigation-and-runtime-experiments.md) | 04, 11 | Low-risk hygiene plus a later local-runtime experiment once routing data exists. |

## How to promote a bundle

1. Start a `feature` run for the bundle unless the bundle file names a tighter workflow.
2. Use the bundle's "First implementation slice" as the run scope.
3. Keep source notes read-only unless the source idea itself needs correction.
4. When a bundle lands, update this index with status and move follow-up work into the next
   smallest bundle or a concrete workflow issue.

## Status

| Bundle | Status |
|---|---|
| 1. Validation and safety foundation | not started |
| 2. Reusable learning loop | not started |
| 3. Planning decision quality gates | not started |
| 4. Run accounting and resume signals | not started |
| 5. Outside cold review sidecar | not started |
| 6. Navigation and runtime experiments | not started |

## Why this order changed from the raw rank

The original ranking was a good benefit list, but execution needs dependency order:

- Preflight, regression capture, battle tests, and external-action gates reduce the blast
  radius of every later workflow.
- Failure learning is strongest after failures have structured signatures and durable
  verification artifacts.
- Decision-quality gates should be installed before adding expensive optional review paths.
- Accounting and local routing are useful, but they should optimize a stable process rather
  than shape an unstable one.

