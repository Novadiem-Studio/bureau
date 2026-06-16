# Novadiem Agent Framework Roadmap

Version: 1.0
Date: 2026-06-15
Status: Consolidated idea -> planning

One-liner: A safety-first, learning-driven, persona-orchestrated framework for turning ideas
into reliable, reusable, verifiable work through the Society of Specialists and The Archive.

## Overview

This roadmap organizes framework evolution into prioritized bundles. The executable backlog
lives in [ideas/agent-framework](../ideas/agent-framework/index.md); this document is the
durable narrative view for framework docs.

For a more public-facing explanation of the vision, see
[The Bureau Learns to Remember](spotlight-bureau-rheo-memory.md).

Rheo persistent memory is included as a boundary-respecting framework integration track
(Bundle 07). Rheo memory itself is remote MOT/Rheo runtime work; the Bureau framework runs
from the local development workspace today. They should converge through explicit contracts
and shared artifacts, not ambient access.

The framework emphasizes:

- Safety and correctness first: reduce the highest blast-radius risks before optimizing.
- Reusable learning: every repeated failure should improve the durable framework layer.
- Decision quality: observable outcomes and explicit assumptions before build work starts.
- Observability and resume: runs should be accountable and easy to re-enter.
- Extensibility last: local runtimes and other optimizations follow data.
- Memory integration as a distinct aligned capability, not hidden global context.

## Bundle Priority and Sequencing

### Bundle 01a - Validation and Safety: Damage Preventers

Purpose: fail fast on missing environment inputs and gate irreversible external actions.

Key deliverables:

- `docs/external-action-boundary.md`: taxonomy plus default rule.
- `[EXTERNAL-ACTION CHECKPOINT]` convention.
- `scripts/preflight.sh`: `.env.example` validation with explicit no-op behavior when no
  `.env.example` exists.

Workflow changes:

- `workflows/execute-plan.md`
- `workflows/operational-build.md`
- `agents/critic.md`

Done when:

- Missing, empty, or placeholder env values block early.
- No external-visible action runs without a logged checkpoint.

Risk:

- Fake safety from loose checks.

### Bundle 01b - Validation and Safety: Process Gates

Purpose: preserve verification across phases and raise promotion standards.

Key deliverables:

- `RUN_DIR/regression/` fixture convention.
- Battle-test matrix for canon promotion.
- Challenger checks for missing representative cases.

Done when:

- Fixtures carry across phases.
- Promotion requires representative cases or an explicit waiver.

Dependency:

- Stronger after Bundle 01a artifacts exist.

### Bundle 02 - Reusable Learning Loop

Purpose: turn failures and corrections into durable framework improvements before run
close-out.

Key deliverables:

- Failure signature format.
- `docs-sync-needed` close-out check.
- `output/studio/lessons.md`.
- Recurrence rule plus convention retirement path.

Memory boundary:

- Rheo memory may surface candidate lessons, but it does not promote framework canon.
- Promotion stays local/framework-driven through Conductor adjudication and Challenger-checkable
  evidence.

Done when:

- Fixes are verified on the smallest representative case.
- Changed artifacts are reconciled.
- Repeated lessons are promoted, deferred with reason, or intentionally scoped local.

### Bundle 03 - Planning Decision Quality Gates

Purpose: ensure work starts from observable outcomes and explicit assumptions.

Key deliverables:

- Required `Outcome / bottleneck` field.
- Greenfield assumption section.
- Bake-off trigger rule.
- Memory citation rule: any assumption closed through Rheo memory must include source,
  confidence, timestamp, and staleness flag.

Done when:

- Non-exploratory specs name an observable outcome.
- Memory-backed assumptions are traceable.

### Bundle 04 - Run Accounting and Resume Signals

Purpose: make runs evaluable and resumable with clear cost, efficiency, model, and history
signals.

Key deliverables:

- `templates/accounting.json`.
- `scripts/account-run.sh`.
- Memory accounting fields when applicable: retrievals, proposed and accepted writes,
  conflicts, digest freshness, and memory preflight status.
- Short accounting pointer in `state.json`; full packet stays in `RUN_DIR/accounting.json`.

Done when:

- Every completed run produces accounting with confidence labels, or a clear unavailable reason.
- Memory usage is visible when memory was used.

### Bundle 05 - Outside Cold Review Sidecar

Purpose: support optional advisory cold review without breaking context isolation.

Key deliverables:

- `templates/external-review.json`.
- `docs/outside-cold-review.md`.
- Memory denied by default; explicit excerpts only when allowlisted with provenance.

Done when:

- Sidecar reviews stay cold and advisory.
- Memory scope is explicitly controlled.

### Bundle 06 - Navigation and Runtime Experiments

Purpose: improve discoverability and explore cheaper local execution for safe tasks.

Key deliverables:

- Warning-only name lint in repo-root `check-framework.sh`.
- Optional `local` runtime adapter, capability-profiled and opt-in.

Memory note:

- Digesting and candidate extraction are possible future local-runtime candidates only after
  quality and cost data justify them.

Done when:

- Linting warns without breaking builds.
- Local routing is proven safe before broad use.

### Bundle 07 - Rheo Memory Framework Integration

Purpose: safely consume and reason about the remote Rheo/MOT persistent memory system from
the local Bureau framework without merging runtimes.

Current boundary:

- Local framework: the Bureau in the local development workspace.
- Remote memory: MOT/Rheo runtime, MCP tools, ledger, bot integration, and service restarts.
- Shared artifacts only until a deliberate adapter lands.

Key rules:

- Read-first adapter contract.
- Memory writes require explicit authority, provenance, conflict behavior, audit trail, and
  Challenger review.
- Memory cannot auto-promote framework canon.
- Cold reviews deny memory by default.

Integration points already reflected:

- Bundle 01: preflight and persistent-state write boundaries for memory tools.
- Bundle 02: memory candidates reviewed before promotion.
- Bundle 03: citation rules for memory-backed assumptions.
- Bundle 04: memory signals in accounting.
- Bundle 05: explicit allowlisting.
- Bundle 06: local runtime candidates only after data.

Timing:

- Bundle 07's rules and checklist exist now.
- Adapter implementation waits until Rheo Layer 0/4 is Challenger-reviewed and deployed, and
  at least one digest/entity phase exists or is explicitly deferred with reason.

Remote memory dependencies:

- Layer 0 + Layer 4 Challenger-reviewed and deployed.
- Session digests exist.
- Versioned graph or equivalent memory receipts exist with provenance and confidence.
- MCP tools are stable enough to expose through a framework-facing adapter.

Done when:

- The framework has explicit contracts, citation rules, accounting fields, and a read-only
  adapter spec, or an intentional deferral.

## Cross-Cutting Principles

- Safety-first sequencing: 01a -> 01b -> 02 -> 03 -> 04 -> 05, with 06 and 07 constrained by
  evidence and dependencies rather than pure priority order.
- Artifact discipline: short pointers in `state.json`; full data lives in `RUN_DIR/`,
  `output/studio/`, or the relevant packet file.
- Challenger role: gates must be Challenger-checkable or script-enforced, not merely
  Conductor-discretionary.
- Studio Record: `output/studio/` is cross-run record space with per-artifact ownership:
  Witness briefings, Bundle 02 lessons, Bundle 04 accounting, and future trend artifacts.
- Runtime boundary: local framework and remote memory remain separate until an explicit
  adapter contract exists.

## Later Visual Follow-Ups

Visual canon updates are valuable but not blockers for the safety/accounting/contracts work.
After memory layers are real enough to depict, update THE CURRENT, THE ENGINE, and
`VISUAL-CANON.md` with memory motifs such as data conduits into The Archive, entity graph
views, and temporal flows.

## Success Criteria

- Runs fail safely and early on configuration or external-action risks.
- Repeated problems improve the reusable layer before the run ends.
- Planning starts from observable outcomes and traceable assumptions, including memory
  citations when memory is used.
- Every completed run is accountable and easy to resume.
- Memory integration is safe, auditable, and does not blur runtime boundaries.
- The framework remains maintainable and evolves through its own learning loop.

## Next Actions

1. Complete and review Bundle 01a.
2. Challenger-review existing Rheo Layer 0/4, route blockers, then hand deployment to The
   Mechanic.
3. Begin Bundle 02 with memory-candidate handling in mind.
4. Keep this roadmap linked to the executable idea files and update it through the reusable
   learning loop.

## Maintenance

This is a living framework document. Update it when a bundle is promoted, split, completed,
or superseded. Keep detailed execution checklists in `ideas/agent-framework/`; keep this file
as the stable narrative roadmap.
