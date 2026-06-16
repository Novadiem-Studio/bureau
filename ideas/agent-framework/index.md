# Agent-framework ideas - execution roadmap

This folder is now organized by execution bundle, not by raw benefit rank. The original
numbered notes are preserved in [`source-notes/`](source-notes/) as source material.

Framework docs roadmap: [docs/roadmap.md](../../docs/roadmap.md).
Spotlight overview: [The Bureau Learns to Remember](../../docs/spotlight-bureau-rheo-memory.md).

The working rule: promote one bundle at a time. Each bundle should become one framework run
or one small series of runs with a clear acceptance boundary. Do not start by implementing
every source idea as a separate mechanism; several of them are the same discipline seen from
different angles.

## Recommended execution order

| Order | Bundle | Source ideas | Why here |
|---:|---|---|---|
| 1a | [Validation and safety — damage preventers](01a-validation-safety-damage-preventers.md) | 13, 07 | External-action gate + `scripts/preflight.sh`; reduces blast radius on the very next run. |
| 1b | [Validation and safety — process gates](01b-validation-safety-process-gates.md) | 14, 08 | Regression fixtures + battle-test matrix; protects later phases and promotions. |
| 2 | [Reusable learning loop](02-reusable-learning-loop.md) | 01, 03, 09 | Turn real failures and repeated fixes into durable framework changes. |
| 3 | [Planning decision quality gates](03-planning-decision-quality-gates.md) | 10, 12, 02 | Improve the quality of specs and architecture choices before build work starts. |
| 4 | [Run accounting and resume signals](04-run-accounting-and-resume-signals.md) | 05, 15 | Make cost, pass count, model mix, and resume context visible after the core loop is stable. |
| 5 | [Outside cold review sidecar](05-outside-cold-review-sidecar.md) | 06 | Add optional advisory review only after artifact boundaries are clear. |
| 6 | [Navigation and runtime experiments](06-navigation-and-runtime-experiments.md) | 04, 11 | Low-risk hygiene plus a later local-runtime experiment once routing data exists. |
| 7 | [Rheo memory framework integration](07-rheo-memory-framework-integration.md) | Rheo memory | Framework-side rules and future adapter seam for consuming remote MOT/Rheo memory safely. |

## How to promote a bundle

1. Start a `feature` run for the bundle unless the bundle file names a tighter workflow.
2. Use the bundle file's "What to build" or "First implementation slice" section as the run
   scope. The original Bundle 01 is deliberately split into two files/runs: Phase 1a, then
   Phase 1b.
3. Keep source notes read-only unless the source idea itself needs correction.
4. When a bundle lands, update this index with status and move follow-up work into the next
   smallest bundle or a concrete workflow issue.

## Status

| Phase | Status |
|---|---|
| 1a. Validation and safety - damage preventers | not started |
| 1b. Validation and safety - process gates | not started |
| 2. Reusable learning loop | not started |
| 3. Planning decision quality gates | not started |
| 4. Run accounting and resume signals | not started |
| 5. Outside cold review sidecar | not started |
| 6. Navigation and runtime experiments | not started |
| 7. Rheo memory framework integration | not started |

## Cross-bundle principle: gate theater

Every gate added by these bundles (preflight, external-action checkpoint, docs-sync check,
outcome metric, coldness receipt, name lint) must be either **Challenger-checkable or
script-enforced**. A gate that is only Conductor-discretionary is theater: the Conductor is
the party with the standing bias to ship. Use the existing Challenger `## Inputs` / cold-
review pattern to enforce gates where a script cannot. Any new gate that fails this test must
be redesigned before it lands.

## Active sibling track: Rheo persistent memory

[Rheo persistent memory](../in-progress/rheo-persistent-memory.md) is already in progress.
It is a sibling MOT/Rheo product track, not an implementation detail of Bundle 02.
The open framework-side integration checklist is tracked in
[Rheo memory framework integration](07-rheo-memory-framework-integration.md).

Deployment boundary today: the Bureau framework runs from the local development workspace;
Rheo memory runs in the remote MOT/Rheo agent runtime. They should be planned as separate
execution surfaces until a deliberate convergence step lands. Convergence should happen
through shared contracts and artifacts first (memory provenance, confidence labels, lessons,
accounting fields, and review receipts), not by letting the local framework assume direct
write access to the remote memory store.

The framework roadmap should integrate with memory through explicit boundaries:

- Phase 1a should distinguish externally visible actions from durable local state writes.
  Remote memory writes are persistent-state mutations in the MOT/Rheo runtime: they need
  provenance, confidence, versioning, and conflict behavior, but only high-risk edits or
  consolidations require human approval.
- Bundle 02 may receive memory-surfaced candidate lessons, but only the framework learning
  loop promotes them into `docs/conventions.md`, runbooks, or `output/studio/lessons.md`.
- Bundle 03 may use memory to reduce assumptions only when cited with source, confidence,
  timestamp, and staleness sensitivity.
- Bundle 04 should account for memory retrievals, writes, conflicts, and digest freshness.
- Bundle 05 denies memory by default; explicit memory excerpts may be allowlisted with
  provenance.
- Bundle 06 may later consider session digesting / candidate extraction as a local-runtime
  workload, after accounting shows quality and cost data.

Likely convergence point: after Rheo memory has Challenger-reviewed Layer 0/4 deployment and
at least one digest/entity phase, add a narrow framework-facing memory adapter that is
read-first, provenance-bearing, and deny-by-default for writes.

## Cross-bundle couplings

- `output/studio/` is the existing Studio Record used by The Witness. Bundle 02 owns
  `output/studio/lessons.md` and any lessons README section, not the whole directory. Bundle
  04 may later reuse the Studio Record for an accounting ledger without redefining ownership.
- Bundle 03 lands before Bundle 05. Outside cold review is not worth its cost until specs
  already name the outcome/bottleneck they should be reviewed against.
- Bundles 04 and 05 both touch `templates/state.json` and `agents/orchestrator.md`; run them
  sequentially and additively, with Bundle 04 first. `state.json` should hold only short
  status/path pointers; the actual packets live in separate files.

## Why this order changed from the raw rank

The original ranking was a good benefit list, but execution needs dependency order:

- Preflight and external-action gates reduce the immediate blast radius; regression capture
  and battle tests then protect later phases and canon promotion.
- Failure learning is strongest after failures have structured signatures and durable
  verification artifacts.
- Decision-quality gates should be installed before adding expensive optional review paths.
- Accounting and local routing are useful, but they should optimize a stable process rather
  than shape an unstable one.
