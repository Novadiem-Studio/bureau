---
priority: bundle-13
status: idea (consolidated)
suggested-workflow: feature
suggested-run-slug: rheo-memory-framework-integration
source-ideas:
  - ../in-progress/rheo-persistent-memory.md
---

# 13. Rheo memory framework integration

## Purpose

Teach the local Bureau framework how to consume and reason about the remote Rheo/MOT memory
runtime without merging the two runtimes by accident.

This is the framework-side convergence track. It records what still needs to be worked into
the Bureau roadmap as Rheo memory becomes real.

## Current boundary

- The Bureau framework currently lives in the local development workspace.
- Rheo memory lives in the remote MOT/Rheo agent runtime.
- They are likely to converge later, but only through explicit contracts and adapters.
- Shared artifacts are the bridge for now: Challenger findings, deploy records, memory
  receipts, cited excerpts, `output/studio/lessons.md`, and future accounting fields.
- The local framework must not assume direct write access to the remote memory store.

## Source documents

- [Rheo persistent memory](../in-progress/rheo-persistent-memory.md) — remote MOT/Rheo production track.
- [Agent-framework roadmap](index.md) — local Bureau framework improvement track.
- [Rheo memory technical vision](../in-progress/rheo-memory-technical-vision.md) — integrated cognitive model, layered architecture, phased roadmap, and success criteria.

## Already worked in

| Concept | Durable home |
|---|---|
| Rheo memory is in progress, not future/backlog | [ideas/index.md](../index.md), [rheo-persistent-memory.md](../in-progress/rheo-persistent-memory.md) |
| Local framework vs remote memory runtime boundary | [rheo-persistent-memory.md](../in-progress/rheo-persistent-memory.md), [agent-framework/index.md](index.md) |
| Longer remote memory production track: Track 0 through Track 4 | [rheo-persistent-memory.md](../in-progress/rheo-persistent-memory.md) |
| Framework integration rules for Bundles 01-06 | [rheo-persistent-memory.md](../in-progress/rheo-persistent-memory.md), [agent-framework/index.md](index.md) |
| Memory cannot promote framework canon by itself | [02-reusable-learning-loop.md](02-reusable-learning-loop.md) |
| Memory-used assumptions need source/confidence/timestamp/staleness | [03-planning-decision-quality-gates.md](03-planning-decision-quality-gates.md) |
| Accounting should include memory signals when memory is used | [04-run-accounting-and-resume-signals.md](04-run-accounting-and-resume-signals.md) |
| External notary review (The Notary) denies memory by default | [05-external-notary-review.md](05-external-notary-review.md) |
| Digesting/candidate extraction may be future local-runtime candidates | [06-navigation-and-runtime-experiments.md](06-navigation-and-runtime-experiments.md) |
| Memory regression/evaluation harness | [rheo-persistent-memory.md](../in-progress/rheo-persistent-memory.md) |

## Still needs to be worked into the framework track

These are not done until the named framework artifact exists and passes review.

### Phase 1a / safety foundation

- [ ] Define persistent-state write boundaries separately from external-visible actions.
- [ ] Clarify that remote memory writes are durable state mutations: provenance, confidence,
  versioning, conflict behavior, and audit trail are required.
- [ ] Human approval is required only for high-risk memory edits/consolidations, not every
  normal memory write.
- [ ] Preflight should eventually include remote memory tool reachability/schema checks when
  a run uses memory.

### Phase 1b / process gates

- [ ] Preserve memory smoke/eval checks as regression fixtures once the fixture convention exists.
- [ ] Define how memory battle-test cases are recorded when a framework run consumes remote
  memory: exact recall, restart recall, conflict behavior, stale fact handling, and false-write
  prevention.

### Bundle 02 / reusable learning loop

- [ ] Define how memory-surfaced candidate lessons are reviewed before promotion.
- [ ] Keep `output/studio/lessons.md` distinct from personal memory facts.
- [ ] Require Challenger-checkable evidence before a memory-surfaced pattern becomes framework
  canon.

### Bundle 03 / planning decision quality

- [ ] Update Analyst, Architect, and Challenger prompts with the memory citation rule.
- [ ] Any assumption closed by memory must cite source, confidence, timestamp, and stale-sensitive
  flag.
- [ ] Memory retrieval can reduce assumptions only when the evidence is visible in the artifact.

### Bundle 04 / accounting and resume

- [ ] Add confidence-labeled memory accounting fields:
  - retrieval count;
  - writes proposed / accepted;
  - conflicts flagged;
  - digest freshness;
  - memory preflight status.
- [ ] Decide whether memory receipts consumed by a local framework run live in `RUN_DIR/`,
  `output/studio/`, or both.

### Bundle 05 / external notary review (The Notary)

- [ ] Encode memory-deny-by-default in the external-review allowlist contract.
- [ ] Any memory excerpt supplied to The Notary must be explicit, allowlisted, and provenance-bearing.
- [ ] The Notary cannot browse remote memory to become "more helpful."

### Bundle 06 / runtime experiments

- [ ] Treat memory digesting and candidate extraction as experimental local-runtime work only
  after accounting proves the workload and quality bar.
- [ ] Local runtime must not write memory directly; it can propose candidates for the remote
  memory write path.

## Future framework-facing adapter seam

- [ ] Define a framework-facing memory adapter contract.
- [ ] Start read-first: `memory_search` / `memory_get` with source, confidence, timestamp, and
  stale-sensitive flag.
- [ ] Deny writes by default from framework workflows.
- [ ] Define write authority separately: allowed operation, payload schema, provenance,
  conflict behavior, and audit trail.
- [ ] Add Challenger review for any adapter that writes remote memory.
- [ ] Add accounting events for adapter reads/writes/conflicts.
- [ ] Decide how Ministry of Flow or The Witness displays memory-related run signals.
- [ ] Update Archive / visual canon after the system is real enough to depict.

## Remote memory dependencies

These are not framework tasks, but the framework integration track depends on them becoming
real in the remote Rheo/MOT track:

- Layer 0 + Layer 4 Challenger-reviewed and deployed.
- Memory smoke results captured.
- Session digesting exists.
- Memory receipts include source, confidence, timestamp, and reason.
- Conflict behavior exists for `write_memory`, `edit_fact`, and `consolidate_entities`.
- Memory quality evals exist for recall, digest accuracy, false writes, conflict handling, and
  staleness.

## Done when

- The local framework has explicit rules for memory citations, memory accounting, and
  memory-deny-by-default outside review.
- A first read-only framework-facing memory adapter is specified or intentionally deferred with
  a reason.
- Any future write path from the local framework to remote memory has a contract, conflict
  behavior, audit trail, and Challenger review.

## Non-goals

- Do not merge the local Bureau framework runtime with remote MOT/Rheo memory by accident.
- Do not give framework workflows ambient write access to remote memory.
- Do not let personal memory facts become framework conventions without Challenger-checkable
  evidence and explicit promotion.

