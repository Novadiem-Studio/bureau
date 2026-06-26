# Agent-framework ideas - execution roadmap

This folder is now organized by execution bundle, not by raw benefit rank. The original
numbered notes are preserved in [`source-notes/`](source-notes/) as source material.

Framework docs roadmap: [docs/roadmap.md](../../docs/roadmap.md).
Spotlight overview: [The Bureau Learns to Remember](../../docs/spotlight-bureau-rheo-memory.md).

The working rule: promote one bundle at a time. Each bundle should become one framework run
or one small series of runs with a clear acceptance boundary. Do not start by implementing
every source idea as a separate mechanism; several of them are the same discipline seen from
different angles.

## Execution queue — do these in this order

This is the **live, authoritative order** for the remaining (not-started) work. The big catalog
table further down is the historical record (original rank + per-bundle status), not the running
order — when the two seem to disagree, this section wins.

**Critical path — strictly sequential, each depends on the one before it:**

1. **[15 — Delegate v2: integrated nesting topology](15-delegate-v2-integrated-nesting.md)** —
   **NEXT.** Spike-validated 2026-06-24. Goes before 11 and 12 because it re-architects the run
   loop, the checkpoint model, and the human-wait boundary that 11 instruments and 12 optimizes.
   Build 11/12 first and you instrument a topology you are about to replace, then redo the hooks.
2. **[11 — Run optimization metrics](11-run-optimization-metrics.md)** — after 15, so it
   instruments the *final* topology. It is also the instrument that proves whether 15 actually
   cut human-wait. Ship before 12.
3. **[12 — Planning loop reduction](12-planning-loop-reduction.md)** — after 11; it needs the
   instrument to show the loop-count reduction actually landed.

**Off the critical path — no fixed slot:**

- **[10 — committed regression suite for `account-run.sh`](10-account-run-committed-regression-suite.md)**
  — parallel-safe and topology-independent (small `execute-plan`). Slot in anytime; a fine quick
  win to run before or alongside 15. Neither blocks nor is blocked by the critical path.
- **[13 — Rheo memory framework integration](13-rheo-memory-framework-integration.md)** — gated on
  remote Rheo/MOT maturity. Do the rules/spec slice whenever convenient; defer the adapter until
  the remote side is ready.

**Follow-on — not yet a bundle:**

- **v3 self-audit gate** — a cold auditor re-reviews a blind sample of `proceed`s; the prerequisite
  for running the Delegate *unattended*. Comes after 15. Promote as its own bundle once v2 is proven
  on real runs. (15 makes *attended* integrated operation clean; unattended waits on this.)

## Bundle catalog — all bundles, by original rank (record, not running order)

For what to do next and in what order, see the **Execution queue** above. This table is the
full catalog with status; the `Order` column is the original benefit rank, not the live sequence.

| Order | Bundle | Source ideas | Why here |
|---:|---|---|---|
| 1a | [Validation and safety — damage preventers](01a-validation-safety-damage-preventers.md) | 13, 07 | External-action gate + `scripts/preflight.sh`; reduces blast radius on the very next run. |
| 1b | [Validation and safety — process gates](01b-validation-safety-process-gates.md) | 14, 08 | Regression fixtures + battle-test matrix; protects later phases and promotions. |
| 2 | [Reusable learning loop](02-reusable-learning-loop.md) | 01, 03, 09 | Turn real failures and repeated fixes into durable framework changes. |
| 3 | [Planning decision quality gates](03-planning-decision-quality-gates.md) | 10, 12, 02 | Improve the quality of specs and architecture choices before build work starts. |
| 4 | [Run accounting and resume signals](04-run-accounting-and-resume-signals.md) | 05, 15 | Make cost, pass count, model mix, and resume context visible after the core loop is stable. |
| 5 | [External notary review (The Notary)](05-external-notary-review.md) | 06 | Add optional advisory cold review via The Notary only after artifact boundaries are clear. |
| 6 | [Navigation and runtime experiments](06-navigation-and-runtime-experiments.md) | 04, 11 | Low-risk hygiene plus a later local-runtime experiment once routing data exists. |
| 8 | [Worktree location hygiene](done/08-worktree-location-hygiene.md) | new (2026-06-19) | **Done** (shipped to main 2026-06-22). Moved execute/bug-fix worktrees outside the target repo so editors and indexers stop choking on a nested worktree. |
| 9 | [Principal delegate](09-principal-delegate.md) | new (2026-06-20) | Two sequenced roles that take Robin out of routine coordination: the **Delegate** (flow + escalation gating — "does Robin need to see this?", build now) and the **Principal** (predicts Robin's call on genuine forks — "what would Robin decide?", a later ledger-trained layer). Ports the proven `CODEX.md` relay pattern; field-tested by hand — the constraint was token burn, so it reasons off run-dir files, not a resumed live session. Complement of Bundle 05 (cold artifact reviewer). |
| 10 | [A committed regression suite for `account-run.sh`](10-account-run-committed-regression-suite.md) | Bundle 04 follow-up | Relocate `account-run.sh`'s 17-case battle-test out of gitignored `output/` into a committed runner (`scripts/tests/account-run/`) so the script carries its own regression coverage. |
| 11 | [Run optimization metrics](11-run-optimization-metrics.md) | Bundle 04 follow-up | Capture tokens / loops / wall-clock / human-wait live into `log.md` via `SubagentStop`+`Stop` hooks. The instrument that tells whether the loop-*cost* (09) and loop-*count* (12) work paid off. |
| 12 | [Planning loop reduction](12-planning-loop-reduction.md) | new (2026-06-20) | Bundle 04 post-mortem → shift-left gates that cut the *number* of correction loops (vs Bundle 09 which cuts their *cost*): an Analyst reconciliation pass after the Architect, a real-log reconciliation requirement for self-observing features, and a script/Scoot artifact-consistency pre-flight before the Challenger. Direct follow-up to Bundle 03; scope against the now-shipped pre-handoff self-checks. |
| 13 | [Rheo memory framework integration](13-rheo-memory-framework-integration.md) | Rheo memory | Framework-side rules + a future read-only adapter seam for consuming remote MOT/Rheo memory safely. Largely gated on remote Rheo/MOT maturity; do the rules/spec slice now, defer the rest. |
| 14 | [Delegate verification gate at integration boundaries](done/14-delegate-merge-gate-verification.md) | Bundle 09 follow-up (2026-06-22) | **Done** (shipped to main 2026-06-23). Gave the shipped Delegate a verifying mode at merge/deploy/promote gates: re-run the claimed gates, scope-diff base...branch, and reproduce any "pre-existing" red at the merge base instead of trusting the build's self-report. Pure mechanical verification (no preference-modeling, stays in FR-44). Tiered so the expensive re-execution runs only at the ~once-per-run integration boundary, resolving 09's token-burn constraint. |
| 15 | [Delegate v2 — integrated nesting topology](15-delegate-v2-integrated-nesting.md) | Bundle 09 v2 (2026-06-24) | Build the Delegate the way it was always meant to be: **Delegate on top**, spawning the Conductor as a subagent the same way the Conductor spawns specialists — replacing v1's Conductor-spawns-Delegate file-mailbox bridge. v1 used the bridge only because nested subagent spawning and subagent resume did not exist yet; both now do (nested spawn v2.1.172; resume via SendMessage). Spike-validated 2026-06-24 (nested spawn + return-on-escalation + resume-with-context, `tool_uses: 0` on resume). Conductor returns on escalation instead of asking Robin (subagents lack AskUserQuestion); coldness preserved via a fresh cold reviewer sub-spawn per checkpoint; Bundle 14's verifying logic moves into it. v3 self-audit (unattended) stays a follow-on. |

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
| 1a. Validation and safety - damage preventers | done — shipped to main 2026-06-17 (preflight.sh + external-action boundary gate) |
| 1b. Validation and safety - process gates | done — shipped to main 2026-06-18 (regression-fixture convention + battle-test promotion gate) |
| 2. Reusable learning loop | done — shipped to main 2026-06-20 (failure-signature convention + recurrence rule + lessons-append gate) |
| 3. Planning decision quality gates | done — shipped to main 2026-06-20 (outcome field + greenfield assumption table + bake-off trigger rule + three Challenger checks + battle-test) |
| 4. Run accounting and resume signals | done — shipped to main 2026-06-20 (`scripts/account-run.sh` + `templates/accounting.json` schema + SPAWN-EVENT close-out convention in `orchestrator.md` + accounting pointers in all terminal workflows). Hardened against an external (Codex) review. Follow-ups: committed regression suite → [idea 10](10-account-run-committed-regression-suite.md); optimization metrics (tokens/loops/wall-clock/human-wait, captured live into `log.md`) → [idea 11](11-run-optimization-metrics.md). |
| 5. External notary review (The Notary) | done — shipped to main 2026-06-20 (cue-packet template + state pointer + model-policy role + protocol doc + completed persona + orchestrator wiring + battle-test matrix; Promotion to canon: yes) |
| 6. Navigation and runtime experiments | done — name-lint hygiene slice shipped to main 2026-06-22 (`check-framework.sh` name lint); local-runtime experiment deferred until accounting shows a real utility workload |
| 8. Worktree location hygiene | done — shipped to main 2026-06-22 (worktrees moved out to `~/.bureau/worktrees/`; run output into `<target>/.bureau/runs/`; cross-run index) |
| 10. A committed regression suite for `account-run.sh` | not started — **parallel-safe / anytime** (off the critical path); Bundle 04 follow-up (execute-plan); relocate the 17-case suite from gitignored `output/` into a committed runner |
| 11. Run optimization metrics | not started — Bundle 04 follow-up; tokens/loops/wall-clock/human-wait captured live into `log.md` (needs SubagentStop+Stop hooks). Ship before Bundle 12 so its loop-count reduction is measurable. |
| 12. Planning loop reduction | not started — idea drafted from the Bundle 04 post-mortem; doctrine-consistent shift-left gates. Reduces loop *count*; complementary to Bundle 09 (loop *cost*). Direct Bundle 03 follow-up. Scope against the now-shipped pre-handoff self-checks. |
| 13. Rheo memory framework integration | not started — largely gated on remote Rheo/MOT maturity; do the read-only adapter spec + framework rules now, defer the rest. |
| 9. Principal delegate | done — spec + plan + scoped prompts shipped 2026-06-20 (agents/delegate.md persona + docs/delegate-bridge.md neutral authority doc + CLAUDE.md three-role contrast table + model-policy.v2.json delegate entry + 7 bridge scripts + 12 regression fixtures). v1 = manual attended path; v2 = autonomous loop; v3 self-audit gate deferred. Principal role explicitly deferred. |
| 14. Delegate verification gate at integration boundaries | done — shipped to main 2026-06-23 (Delegate verifying mode at integration gates: P1 request/scope contracts → P5 Track-3 regression fixture, promoted to the standing suite). Bundle 09 follow-up; satisfied the 2026-06-22 priority override |
| 15. Delegate v2 — integrated nesting topology | not started — **NEXT UP** (critical path); idea, **spike-validated 2026-06-24**. The intended topology (Delegate spawns Conductor as a subagent, not the reverse), now unblocked by nested subagent spawning (v2.1.172) + subagent resume (SendMessage). Re-architects v1's file-mailbox bridge into in-session Agent-tool orchestration; Bundle 14's verifying logic survives in a cold reviewer sub-spawn. v3 self-audit (unattended operation) remains a separate follow-on prerequisite |

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
[Rheo memory framework integration](13-rheo-memory-framework-integration.md).

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
- Bundle 03 lands before Bundle 05. External notary review is not worth its cost until specs
  already name the outcome/bottleneck they should be reviewed against.
- Bundles 04 and 05 both touch `templates/state.json` and `agents/orchestrator.md`; run them
  sequentially and additively, with Bundle 04 first. `state.json` should hold only short
  status/path pointers; the actual packets live in separate files.
- Bundle 09 (Principal delegate) and Bundle 05 (The Notary) are complements on the coldness axis,
  not a shared dependency: 05 is a cold *artifact* reviewer; 09 is a warm *process* reviewer that
  reads `log.md` on purpose, to judge how the Conductor handled the Challenger. 09 needs no
  Challenger-findings split — an earlier draft assumed it did. They can ship in either order.
- Bundles 09 and 10 attack the same pain (correction loops) from opposite ends and are
  independent: 10 makes loops *fewer* (shift catches left to the producer), 09 makes them *cheaper*
  to review. Both came out of the Bundle 04 post-mortem. If both land, the delegate reviews a
  pipeline that already produces fewer loops — but neither blocks the other.

## Why this order changed from the raw rank

The original ranking was a good benefit list, but execution needs dependency order:

- Preflight and external-action gates reduce the immediate blast radius; regression capture
  and battle tests then protect later phases and canon promotion.
- Failure learning is strongest after failures have structured signatures and durable
  verification artifacts.
- Decision-quality gates should be installed before adding expensive optional review paths.
- Accounting and local routing are useful, but they should optimize a stable process rather
  than shape an unstable one.
- Bundle 15 (Delegate v2) precedes 11 and 12 because it re-architects the run loop those two
  instrument and optimize. Instrumenting the v1 loop first (11's SubagentStop+Stop hooks,
  measured at v1 `[CHECKPOINT]` prompts) would be thrown away once the Conductor becomes a
  subagent and the human-wait boundary moves to escalation. Settle the topology, then measure it.
