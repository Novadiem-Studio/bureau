# Session Change Overview - Assistant Service Context

This document summarizes the Bureau framework changes made during the July 2026 working
session and why they matter. It is written as service context for a future assistant that needs
to understand the current architecture, what changed, and how data now flows through the
framework.

## Executive Summary

The session moved the Bureau framework from a strong cold-review loop toward a better shaped
work system before cold review begins. The central improvement was not "make the Delegate reduce
Critic findings." The Delegate-default change fixes the operator interface and topology. The
likely quality and cost improvements come from the other changes: clarify product decisions
before specs, make test seams explicit before build, preserve durable architecture decisions in
target repos, sharpen build-diff review, and require bug fixes to prove the reported symptom
before changing code.

The intended outcome is fewer late Critic blockers, fewer ambiguous human checkpoints, and more
runs with this shape:

1. One or two early blockers, while the artifacts are cheap to revise.
2. Prompt review with no build-shaping blockers.
3. Build-diff review that keeps minor issues as warnings.
4. Concrete fixtures, tests, or live smoke evidence at close-out.

The Novadiem `/ai-assessment` build was the main observed example discussed in-session: one real
early Critic blocker, then clean prompt/build-diff reviews and live verification. That is evidence
for the execute-plan/build-tail/review machinery, not proof that Delegate-default itself reduced
Critic findings.

## Landed Commits

The session landed these commits on `main` / `origin/main`:

- `0005801` - advanced bundles 32-34: seam-first testing, two-axis build-diff review, and the
  grilling checkpoint.
- `348790e` - added ADR decision-record discipline.
- `87c9827` - added bug-diagnosis discipline.
- `2a34701` - made the integrated Delegate path the default Bureau entrypoint.
- `db204d1` - removed operator-facing Delegate version labels from entrypoint docs.
- `ce88180` - clarified the Delegate self-audit corpus gate.
- `ea3e90a` - filed the MOL multi-platform Braintrust idea.
- `67fb6fb` - recorded the recent Delegate-default run evaluation.

At the time this context was first written, there were additional uncommitted workspace changes
in `agents/delegate.md`, `config/calibration-exemplars/`, `config/model-policy.v2.json`, and
`docs/evaluation/framework-evaluation-log.md`. Treat those as current workspace state, not as
landed changes covered by this document.

## Architectural Breakdown

### 1. Entrypoint And Topology

New Bureau runs now start with The Delegate by default.

Relevant files:

- `AGENTS.md`
- `CLAUDE.md`
- `agents/delegate.md`
- `agents/orchestrator.md`
- `docs/delegate-bridge/v2-integrated.md`
- `scripts/run-start.sh`

When Robin says "get the bureau on this," "run the bureau," or similar, the correct default is:

```text
Robin
-> Delegate manager/relay session
-> Conductor resumable subagent
-> specialist subagents
```

Direct Conductor mode remains available only when Robin explicitly asks to bypass the Delegate,
when resuming a legacy/non-integrated run, or when the host/runtime cannot support the integrated
Delegate topology.

The Delegate is not a preference model and does not decide "what Robin would want." Its job is
flow and gating: stage checkpoint context, run deterministic gates, call a cold reviewer, record
the verdict, and resume or escalate.

### 2. Run Initialization

`scripts/run-start.sh` is the run opening ceremony. It creates the run directory, initializes
`state.json` and `log.md`, writes a runs-index entry, resolves model routing, and enrolls the
normal run pointer.

Delegate mode calls:

```sh
scripts/run-start.sh "$RUN_DIR" --target "$TARGET_REPO" --workflow "$WORKFLOW" --slug "$SLUG" --no-pointer-echo
```

`--no-pointer-echo` matters because the normal bare pointer nonce is the specialist-spawn
post-hoc membership credential. In integrated Delegate mode, that nonce must not enter the
Delegate transcript. The Conductor reads it privately and includes it only in specialist spawn
prompts. The former separate `role:delegate` pointer and live-hook capture rail have since retired;
terminal accounting recovers Claude legs from JSONL, while Codex records a named per-leg gap.

### 3. Planning Quality Layer

The planning layer gained three major disciplines.

**Grilling discipline**

File: `docs/conventions/grilling.md`

The Analyst runs a pre-spec grill screen in the `feature` workflow. It raises one batched
checkpoint only when a material decision would otherwise be guessed into the spec. Every
checkpoint item must include a recommended default and explain the impact if Robin changes it.

This targets rework caused by bare assumptions, especially user facts such as timezone, locale,
audience, recipient, account, production target, or external service.

**ADR decision records**

File: `docs/conventions/adr-records.md`

Target repos may carry durable decisions in:

```text
<target-repo>/docs/adr/0001-short-slug.md
```

Accepted ADRs are read as target-repo ground truth. The Analyst and Architect read them in
existing-project mode, the Architect writes or supersedes them only for qualifying decisions,
and the Challenger blocks specs/plans that contradict accepted ADRs unless a superseding ADR is
included.

This does not make cold review warm. The Challenger is still cold to the current run rationale,
prior findings, and `log.md`; it is only reading committed project facts.

**User-fact provenance**

The grilling work also tightened user-fact sourcing. Load-bearing facts about Robin, users,
locale, deadlines, production targets, external tenants, or recipients must be sourced from the
brief, `project-context.md`, repo evidence, resolved grill answers, or a memory citation. If no
safe default exists, the fact belongs in open questions rather than as a silent assumption.

### 4. Build And Review Layer

The build layer now pushes reviewers and coders toward concrete, reviewable evidence.

**Seam-first testing**

File: `docs/conventions/tdd-seams.md`

Every build prompt's `## Checkpoint` starts with one of:

```markdown
Seams under test: <named public seam(s) and behavior pinned>
```

or:

```markdown
Seams under test: none - <short reason>
```

The seam should be a public observable boundary: HTTP request/response, CLI output, reducer
transition, rendered user behavior, job side effect, persisted invariant, or integration
contract. Non-`none` seams should be mutation-verified by briefly breaking the guarded behavior,
observing the test fail, restoring the code, and rerunning green.

**Two-axis build-diff review**

Files:

- `agents/critic/build-diff.md`
- `docs/conventions/fowler-smell-baseline.md`

Build-diff review now separates:

1. Spec-fidelity: does the diff build what the approved spec/prompt required?
2. Standards: does the diff meet target-repo standards and baseline design hygiene?

The axes are not cross-ranked. A standards warning should not disguise a spec bug, and a
spec-faithful change can still carry maintainability warnings. The Standards axis loads a small
Fowler-inspired smell baseline only when project standards are silent.

This is intended to reduce noisy rework: genuine "would build the wrong thing" issues remain
blockers; cosmetic or low-risk maintainability issues can stay warnings.

### 5. Bug-Fix Layer

File: `docs/conventions/diagnosing-bugs.md`

The `bug-fix` workflow now has a sharper diagnosis contract:

1. Create a red-capable feedback loop before locating or fixing the cause.
2. Minimize the repro before theorizing.
3. If the cause remains foggy, generate 3-5 falsifiable hypotheses and use targeted probes.
4. Remove all temporary instrumentation before handoff.
5. Leave a committed regression test at the correct target-repo seam whenever one exists.
6. Use `RUN_DIR/repro.md` as the single cold artifact for symptom, loop, cause, regression
   evidence, and debug cleanup.

This avoids "plausible fix" behavior. A bug fix must demonstrate the reported symptom failing
before the fix and passing after the fix, or explicitly record why no correct seam exists.

### 6. Evaluation And Queue Layer

The idea queue was updated so bundles are promoted in evidence-first order rather than raw
benefit rank. The Matt-transplant series now sits in the queue as bundles 32-39:

- 32 - seam-first testing: implementation landed, measurement pending.
- 33 - two-axis build-diff review: done.
- 34 - grilling decision checkpoint: implementation landed, measurement pending.
- 35 - ADR decision records: implementation landed, measurement pending.
- 36 - bug-diagnosis discipline: implementation landed, measurement pending.
- 37 - living glossary: gated.
- 38 - architecture-care workflow: later opt-in workflow.
- 39 - Wayfinder: later foggy-work mapping workflow.

The Delegate self-audit gate remains bundle 20 and is explicitly gated. It should not start
until there is enough attended Delegate verdict corpus collected after the default-entrypoint
fix.

## Primary Data Flows

### New Run Flow

```text
Robin request
-> AGENTS.md default entrypoint
-> Delegate reads agents/delegate.md and docs/delegate-bridge/v2-integrated.md
-> workflow triage via workflows/index.md
-> run-start.sh creates RUN_DIR/state/log/index/model-routing/pointer
-> Delegate records transcript identities; Conductor privately reads the run-scope nonce
-> Delegate spawns Conductor with RUN_DIR and BUREAU_ROLE: conductor
-> Conductor dispatches specialists
```

### Planning Flow

```text
Analyst grill screen
-> optional GRILL checkpoint or skip
-> requirements/spec
-> Architect reads accepted ADRs when present
-> Architect writes spec/plan and qualifying new ADRs
-> Challenger cold spec-plan review
-> Spellwright writes scoped prompts with AC/checkpoint/seam contracts
-> Challenger cold prompt review
```

### Build Flow

```text
Prompt folder
-> isolated worktree
-> prior fixtures rerun
-> coder builds one prompt
-> coder commits
-> Challenger build-diff review on Spec-fidelity + Standards
-> Conductor adjudicates
-> fixtures/live smoke
-> integration or deploy boundary
```

### Delegate Checkpoint Flow

```text
Conductor returns CONDUCTOR-RETURN block
-> Delegate stages checkpoint context only
-> headless cold reviewer reads artifact + log-slice + state projection
-> JSON verdict: proceed / revise / escalate
-> artifact hash binding checked
-> Delegate records decision and resumes Conductor or escalates to Robin
```

### Bug-Fix Flow

```text
User reports bug
-> bug-fix workflow
-> repro.md records symptom
-> red-capable loop created
-> repro minimized
-> cause located or hypotheses/probes run
-> fix implemented
-> regression test added at correct seam
-> pre-fix red and post-fix green evidence recorded
-> Challenger build-diff bug regression gate
```

### Evaluation Flow

```text
RUN_DIR logs/state/verdicts/accounting
-> framework evaluation ledger
-> measured blockers, loops, token capture, and Delegate verdict corpus
-> idea queue gates
-> bundle status updates
```

## Key Operational Rules For Future Assistants

- Start new Bureau runs with The Delegate by default.
- Do not ask Robin to say "run as Delegate" for normal Bureau use.
- Bypass Delegate only on explicit request, legacy/non-integrated resume, or runtime inability.
- Do not describe "Delegate v2" or "Delegate v3" as choices Robin has to make. Normal operation
  is "The Delegate"; the self-audit bundle is a future unattended-readiness gate.
- Do not count old direct-Conductor runs as Delegate self-audit corpus, though they can inform
  failure taxonomy.
- Attribute likely Critic-count improvements to shift-left planning, AC mapping, seam testing,
  two-axis build-diff review, and fixture/live-smoke discipline, not to Delegate-default itself.
- Treat `docs/adr/` as durable target-repo decision memory, not run history.
- Keep `CONTEXT.md` glossary work out of ADRs until bundle 37 ships.
- For bug fixes, do not skip the red-capable repro loop unless a checkpoint records why it cannot
  be built.

## Current Assessment

The non-Delegate framework changes are promising. The Novadiem `/ai-assessment` build showed the
desired pattern: one early blocker on a public money-spending endpoint, then clean prompt and
build-diff reviews with live verification of the risky branches.

This is not yet statistically proven. The next useful evidence is completed runs showing:

- fewer late build-diff blockers;
- fewer prompt-review blockers caused by missing AC or contract details;
- lower `test-coverage-gap` findings after seam-first prompts;
- net-positive grilling results, where rework saved exceeds added human checkpoint wait;
- ADR reuse in a later run within the same target repo;
- bug-fix runs with real pre-fix red and post-fix green tests.

Bundle 37 should wait until 35 has mileage, 34 has net-positive evidence, and docs-reconcile has
proved it can keep prose artifacts from decaying. Bundle 20 should wait until the attended
Delegate corpus threshold is met. Bundle 21 remains last by Robin's directive.
