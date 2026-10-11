# Workflow: bureau-lite

**When to use:** a feature or substantial change that needs a short spec and a phased plan and
will take more than one build session, but whose likely bugs mostly announce themselves. Robin
names it ("bureau-lite", "lite run", "lighter cadence"), or triage picks it for a task that
clears every bar under When NOT to use. Also the target when Robin downshifts a running
`feature`, `execute-plan` or `design-build` build (see § Downshifting a running build). The
reference case is rheo-stream's `20261010-upwork-collector` run (OAuth client, token storage, a
scheduled collector, about 25 build units), which Robin moved to this cadence partway through.

**When NOT to use:**
- **Money movement:** pricing, payments, payouts, ledgers, balances, invoices → `feature` then
  the `execute-plan` build tail. The `money` risk tag escalates if it shows up anyway.
- **Destructive or data-rewriting migrations:** drops, renames, truncates, backfills that
  rewrite rows → `feature` + build tail. The `destructive-migration` tag escalates.
- **Public shipping as the deliverable:** a release, a publish, a production deploy, anything
  whose point is to go out under Robin's name → `feature` + build tail, with Robin at the gate.
  (No workflow ships past dev on its own; this one is simply not the right size for the release
  itself.)
- **An authz rewrite across a tenancy boundary**, or any change Robin has marked sensitive in
  `project-context.md` → `feature`.
- **One self-contained change** you can just build with no spec or plan → `build-review-cold`.
- **A known defect** to reproduce and fix → `bug-fix`.
- **An existing plan doc** (`plans/todo/NN-*.md`) → `execute-plan`.
- **A change to the Bureau's own canon** (`workflows/`, `agents/`, `docs/conventions*`) →
  `execute-plan`, which carries the promotion and battle-test gate.

**Type:** mixed (plans with one Challenger round, then builds unit by unit with risk-triggered
review, in one run).

**Inputs:** the task brief; `project-context.md` if present (including any ` ```json risk_tags```
` block, § Risk tags); in existing projects, the workspace orientation ("Existing-project mode"
in `agents/orchestrator.md`) and the per-sub-app skills the affected surfaces need. Out of
scope: anything past dev (production boundary) and any external action without its checkpoint.

**Outputs:** under `RUN_DIR` (`docs/run-protocol.md`): `spec.md`, `plan.md` (phases holding
build units), `log.md`, `state.json`, one `risk-tags/<NN>.json` record per build unit,
`integration-results.json` per integration gate, `github/` delivery evidence, `accounting.json`.
Optional: `prompts/` (coarse prompts, step 6) and `design/` (only when the plan names a UI that
needs a Claude Design pass). The change itself lands on the dev/integration branch through the
linked PR (or the recorded local fallback).

**Leans on skills:** **novadiem-engineering** (Architect, Challenger, every coder) + the
project's `testing` skill and per-sub-app skills. Scripts: `scripts/run-start.sh`,
`scripts/preflight-artifacts.sh`, `scripts/run-worktree.sh`, `scripts/pr-delivery.sh`,
`scripts/coderabbit-pass.sh`, `scripts/risk-tags.sh`, `scripts/integration-gate.sh` (the
Delegate's), `scripts/terminal-pairing.sh`, `scripts/account-run.sh`.

## Objective

Ship a planned, multi-unit change to dev with the review spent where a wrong result would not
announce itself: one cold read of the design, a cold read of each build unit whose diff touches
an enumerated risk surface, an integration gate at every phase boundary, and one whole-PR cold
review at the end.

## Where it sits

| | `build-review-cold` | **`bureau-lite`** | `feature` + `execute-plan` build tail |
|---|---|---|---|
| Spec / plan | none | one pass, Analyst + Architect | Analyst, Architect, reconciliation |
| Pre-spec grill checkpoint | no | no (open questions ride the design gate) | yes, when triggered |
| Design-model checkpoint | no | **yes** | yes |
| Challenger on the design | no | **one round** | round 1, up to 2 fix loops |
| Prompts | none | optional, coarse | Spellwright + Challenger round 2 |
| Per-unit cold review | at most one, whole diff | **only units `risk-tags.sh` flags** | every prompt |
| Integration gates | none | phase boundaries, post-merge, final | phase boundaries, post-merge, final |
| Terminal whole-PR cold review | the one review | yes | yes |

## Steps

Run these as spawned subagents where named ("How to spawn an agent" and "Model routing" in
`agents/orchestrator.md`). Pass `RUN_DIR` as an absolute path in every spawn prompt. Topology is
the build-run default: the Delegate is top level and spawns the Conductor (`CLAUDE.md § Default
entrypoint`). Start the run with
`scripts/run-start.sh <RUN_DIR> --target <repo> --workflow bureau-lite` (Delegate mode adds
`--no-pointer-echo`); `run-start.sh` refuses an id with no matching `workflows/<id>.md`.

1. **Analizer 2000** (Analyst, **standard**) — requirements, scope, edge cases, and a closing
   `## Open questions` list → `spec.md` (Requirements)

   No grill checkpoint. Questions the Analyst would have grilled on go in `## Open questions`,
   each with a recommended default, and travel to the design-model checkpoint (step 4). That
   folds two human stops into one.

2. **The Architect** (**strong**) — architecture and a phased plan of build units → `spec.md` (Architecture), `plan.md`

   `plan.md` is organized as `## Phase N: <name>` sections (the integration cadence reads them,
   `docs/conductor-gates.md § Integration checkpoint cadence (build runs)`). Each phase lists
   its build units, numbered across the run:

   ```
   ### Unit 07: token-store
   Coder: The Systemsmith
   Files: app/upwork/token_store.py, tests/test_token_store.py
   Does: <two or three lines a fresh coder can act on>
   Checkpoint: pytest tests/test_token_store.py -q
   Risk forecast: tokens-secrets
   ```

   One unit = one coder, one sub-app, one diff a reviewer can read in a sitting (the
   review-size rule of `workflows/execute-plan.md` step 3 applies to units too). `Risk
   forecast` names the tags from § Risk tags the Architect expects the unit to trip. It is a
   forecast for Robin's planning, not the trigger; `risk-tags.sh` decides at build time. A unit
   forecast to trip an `escalate` tag means the task fails When NOT to use: the Architect says
   so at the top of `plan.md` and the Conductor raises it at step 4.

   There is no reconciliation spawn. Step 3 checks FR coverage mechanically and the Challenger
   reads Requirements against Architecture in step 5.

3. **The Conductor** — `scripts/preflight-artifacts.sh "$RUN_DIR" --phase round1` → `log.md` (preflight result)

   Mechanical: presence, FR/EC/AC coverage and dangling references across `spec.md` and
   `plan.md`. A defect routes back to the Architect (or the Analyst for a Requirements gap)
   before the design gate. Robin should not see a plan that fails a script.

4. **Gate** — the design-model checkpoint, mandatory. `[DESIGN-MODEL CHECKPOINT]`

   The Conductor shows Robin the Architect's design-model summary and over-baseline mechanism
   list ("Design-model checkpoint" in `agents/orchestrator.md`), the Analyst's open questions
   with their defaults, the phase list with unit counts, and the risk forecast rolled up per tag
   ("Phase 2: 6 units, 4 forecast to trip oauth-auth or tokens-secrets"). The protocol is
   `agents/orchestrator.md § Design-model checkpoint` as written, with these items added to its
   output; it reaches Robin the same way it does on a `feature` run, and only Robin answers it.
   Robin's go here is also the build go, unless step 5 changes the design model. If the
   forecast names an `escalate` tag, recommend `feature` + build tail instead and let Robin
   choose; record the choice in `log.md`.

5. **The Challenger** (Critic, the one design round, **strong**, fresh context required) — review `spec.md` + `plan.md` cold → `log.md`, findings

   Brief: requirement gaps, Requirements vs. Architecture drift, wrong phase order, hidden
   cross-unit dependencies, units too large to review, and risk forecasts that look wrong.
   **The Conductor adjudicates**, one fix loop only: route each accepted finding to the
   Architect (or the Analyst), then check the revision against the finding list itself. There is
   no second Challenger round. Two exceptions:
   - a fix that changes the design model Robin approved goes back to Robin as step 4 again,
     once;
   - a Blocker still open after its one fix is a `[CHECKPOINT]` (`genuine-fork`, signal 7).

6. **The Spellwright** (Prompt Engineer, optional, **standard**) — coarse prompts, one per unit or one per phase per coder → `RUN_DIR/prompts/`

   Default: skip this step. The build units in `plan.md` are the coder briefs. Run it only when
   Robin asks for prompts, when the build will run outside this session (prompts as a
   hand-off), or when the Conductor finds a unit too thin for a fresh coder to act on from
   written context alone (then prefer sending that unit back to the Architect). When it runs, it
   follows `workflows/execute-plan/prompt-folder-format.md`, tags `Coder:` on every prompt, and
   no Challenger round follows. `preflight-artifacts.sh --phase final` treats prompts as optional
   for `bureau-lite` when none exist and checks them normally when they do.

7. **Worktree** — create the worktree, issue and draft PR, then run preflight; build-tail steps 5b and 5c, unchanged → `state.json` (`git` block), `RUN_DIR/preflight.md`

   `workflows/execute-plan/build-tail.md` 5b and 5c: `run-worktree.sh create`, acceptance
   criteria into `RUN_DIR/github/issue.md`, `pr-delivery.sh open` before the first coder
   dispatch, `preflight.sh` must show PASS. Copy the project's `integration_gate` block into
   `state.json` as usual.

8. **The Conductor** (**strong**) — build the units in order, 01..NN, through the build tail's step 6 with one substitution → a committed, risk-tagged diff per unit, `RUN_DIR/risk-tags/<NN>.json`

   Everything in `workflows/execute-plan/build-tail.md` step 6 applies as written: the
   prior-fixture re-run gate and standing suite before every dispatch, the CI read between units
   on a GitHub-delivered run, `Coder:` tag dispatch, the coder's own green checkpoint in the
   foreground, the CodeRabbit pass and its dispositions, the Cleric review for UI units when a
   `design/manifest.md` exists, the review-size gate, fixture capture on accept, parallel-track
   limits, failure repair, and both boundaries. The substitution is the build tail's bullet
   "**The Challenger** cold-reviews that single diff". Under `bureau-lite` that review runs only
   when the risk-tag check says so. Per unit:

   a. Before dispatch, record the unit base: `UNIT_BASE=$(git -C "$WORKTREE" rev-parse HEAD)`,
      taken after any base-branch merge so the range holds only this unit's commits.
   b. The coder builds and commits; the checkpoint is green.
   c. The CodeRabbit pass runs and its dispositions are recorded (build tail step 6).
   d. Run the check on the unit's whole range, CodeRabbit fixes included:
      ```sh
      scripts/risk-tags.sh --worktree "$WORKTREE" --base "$UNIT_BASE" \
        --out "$RUN_DIR/risk-tags/<NN>.json"
      ```
      and log `RISK-TAGS: unit <NN> <result> [<tags>] → risk-tags/<NN>.json` with
      `scripts/log-append.sh`.
   e. Route on the exit code. Never on a reading of the diff:
      - **0 clean** → the coder's tests and the CodeRabbit dispositions are the review. The
        Conductor adjudicates acceptance on those and the review-size gate.
      - **1 review** → step 9 runs on this unit before it can be accepted.
      - **2 error** → fail closed: step 9 runs, and the Conductor logs the error. If the cause
        is the config or the project block, fix it before the next unit.
      - **3 escalate** → stop dispatching. Return a `genuine-fork` (signal 6) naming the unit,
        the tag and the record path. Robin either upshifts the run (§ Downshifting a running
        build, last part) or keeps it lite. Either way this unit gets step 9, and a keep-lite
        answer is logged as `RISK-TAGS waiver: unit <NN> <tag>; by Robin: "<Robin's words>"`.
   f. The Conductor may add a review the script did not ask for: log
      `REVIEW-ADD: unit <NN>: <one-line reason>` and run step 9. It may never skip one the
      script asked for. Only Robin can waive a `review` result, per unit, logged as above.
   g. A risky change the patterns missed (found by an integration gate, the terminal review, or
      a REVIEW-ADD) is a failure signature (`docs/conventions/failure-signatures.md`). The build
      tail's failure-repair rule promotes the fix into a durable artifact: a pattern in the
      project's `risk_tags` block, or a PR to `config/risk-tags.json`.

9. **The Challenger** (Critic, build-diff, **strong**, fresh context required) — cold review of one flagged unit → `log.md`, findings

   Only for units step 8e or 8f sent here. Spawned cold per the build-diff slice
   (`agents/critic/build-diff.md`) and the cold-reviewer recipe
   (`docs/delegate-bridge/v2-integrated.md § v2 §3`). It gets the unit's diff, the unit brief
   from `plan.md` (or its prompt), the risk-tag record and the dispositioned CodeRabbit findings
   file. It does not get `log.md` or the coder's reasoning. Its question: **"on the surfaces
   these tags name, what here corrupts, leaks, miscounts or fires WITHOUT announcing it?"**,
   plus scope against the unit brief. **The Conductor adjudicates**: accept, route the fix back
   to the coder (max 2, `max_critic_loops`), or `[CHECKPOINT]`.

10. **Gate** — integration checkpoints, unchanged: phase boundaries, after any base-branch merge, and the final gate. `[CHECKPOINT]`

    The Conductor returns `routine-checkpoint` with `checkpoint-subtype: integration` and the
    right `gate-point` after the last accepted unit of each phase (`docs/conductor-gates.md §
    Integration checkpoint cadence (build runs)`). The Delegate runs `integration-gate.sh` and
    one cold reviewer, as on any build run. Accepting a unit is never a checkpoint, so the
    Delegate's cold reviews in this workflow happen at the design gate's adjudication, these
    integration gates and the terminal review.

11. **The Conductor** (**strong**) — close out through build-tail step 7, unchanged → `log.md`, `state.json`, `github/evidence.md`, `accounting.json`

    Fixture promotion, the terminal whole-PR cold review paired with a green final gate on the
    same head SHA (`scripts/terminal-pairing.sh`), the close-out gates (preflight PASS,
    external-action log, `docs-sync-needed`, `lessons-append`), merge by the resolved delivery
    path (a merge commit, never a squash), worktree removal, and `account-run.sh` last. One
    addition: before the evidence file is published, log a coverage line and copy it into
    `github/evidence.md`:
    `REVIEW-COVERAGE: <N> units; clean <C>; reviewed <R> (tagged <T>, error <E>, review-add <A>); escalated <X>; waived <W>`.
    Then run `scripts/preflight-artifacts.sh "$RUN_DIR" --phase final`.

> **Production boundary and external-action boundary.** Both apply exactly as in
> `workflows/execute-plan/build-tail.md` ("Production boundary — hard stop" and
> "External-action boundary — separate gate"). A unit that trips `external-irreversible` gets
> its cold review AND still raises the `[EXTERNAL-ACTION CHECKPOINT]` before anything fires.
> The risk tags never replace either gate.

## Risk tags

`config/risk-tags.json` is the authoritative list and `scripts/risk-tags.sh` applies it. Each
tag matches changed file paths and changed (added or removed) lines with case-insensitive
patterns. Docs, lockfiles and binary assets are ignored. The record names files, line numbers
and the pattern that matched, never the line text, since a flagged line may hold a secret.

| Tag | Class | Covers |
|---|---|---|
| `oauth-auth` | review | OAuth flows, auth callbacks, PKCE/CSRF/JWT, authentication and authorization checks |
| `tokens-secrets` | review | token storage, secret store, credentials, API and private keys, crypto, `.env` files |
| `network-egress` | review | server-side outbound HTTP/sockets, webhooks, host and origin allowlists, CORS |
| `tool-allowlist` | review | agent tool allowlists, `.claude/settings*.json`, MCP server config, permission modes |
| `redaction` | review | redaction, PII scrubbing, masking, logging calls that carry tokens or secrets |
| `durable-state` | review | additive migrations and DDL |
| `external-irreversible` | review | email/SMS/notification sends, DNS/infra mutation, deploy commands, recursive deletes |
| `concurrency` | review | locks, transactions, idempotency and dedup, schedulers and cron, launchd plists |
| `money` | escalate | payments, payouts, refunds, invoices, ledgers, billing, pricing, balances |
| `destructive-migration` | escalate | drop/rename/truncate/delete/update-set inside migration or SQL files |

The first five are the set Robin set on the upwork-collector run; the rest map
`build-review-cold`'s five silent-failure surfaces, so the two gears agree on what counts as
risky.

A project adds to the list with a block in `project-context.md`, committed on the base branch.
`risk-tags.sh` reads it with `git show <base>:project-context.md`, so a run cannot loosen its
own triggers:

````
```json risk_tags
{"tags": [
  {"id": "upwork-api", "class": "review", "description": "Upwork GraphQL client",
   "paths": ["(^|/)upwork/client"], "lines": ["api\\.upwork\\.com"]},
  {"id": "concurrency", "lines": ["collector_lock"]}
]}
```
````

A project may add tags, add patterns to an existing tag, or raise a tag to `escalate`. It may
not set `ignore_paths`, lower a class, or narrow a default tag with `line_scope`; any of those
makes the script exit 2 (fail closed). Changing a default pattern is a PR to
`config/risk-tags.json` with a regression fixture, like any other script change.

The tags are a floor. Over-firing costs one cold review; under-firing is the failure the
workflow exists to prevent, so when a pattern is noisy, narrow it by PR rather than by
skipping reviews in a run.

## Selecting bureau-lite at run start

- Robin names it, or triage picks it per `workflows/index.md` after checking every When NOT to
  use bar. Log the triage line as usual, naming the bar that was closest.
- `scripts/run-start.sh <RUN_DIR> --target <repo> --workflow bureau-lite` writes
  `state.json#workflow: "bureau-lite"` and `workflow_shifts: []`. The Delegate bootstrap passes
  the same id when it spawns the Conductor.
- If `project-context.md` holds a `risk_tags` block, the Conductor notes it in `log.md` at run
  start, so the extra triggers are visible before the first unit.

## Downshifting a running build

A `feature`, `execute-plan` or `design-build` run can move to this cadence mid-run. Only Robin
can make that call. The Conductor or the Delegate may suggest it in a checkpoint relay ("12 of
25 prompts left, 3 forecast to touch credential code"), but neither applies it on its own.

**When it takes effect.** At a unit boundary. The prompt or unit in flight finishes under the
old cadence, including its Challenger review if one has started. Reviews already run stand. A
downshift during planning drops the planning steps this workflow does not have (reconciliation,
a second Challenger round, the Spellwright and the prompts Challenger round when the plan
already has units); steps already completed stay in the record.

**What changes.** From `effective_from` on, step 8's per-unit routing replaces the build tail's
every-prompt Challenger. Existing prompts in the prompt folder become the units, in order;
their `Coder:` tags stand. Integration gates, CodeRabbit, fixtures, the terminal review and both
boundaries do not change.

**What gets recorded, in order:**

1. The session Robin spoke to logs his instruction with a real clock read. In Delegate
   topology that is the Delegate, which also relays it to the Conductor on the next resume:
   ```sh
   scripts/log-append.sh "$RUN_DIR" "WORKFLOW-SHIFT: execute-plan → bureau-lite from unit 10" - <<'EOF'
   by: Robin, "<Robin's words, verbatim>"
   effective_from: 10   (09 finishes under the old cadence)
   changes: per-prompt Challenger only on units risk-tags.sh flags
   unchanged: integration gates, CodeRabbit, fixtures, terminal review, boundaries
   EOF
   ```
   `delegate-state.json` does not change: per-unit reviews are not Delegate checkpoints.
2. The Conductor appends to `state.json#workflow_shifts` (it owns `state.json`), validates the
   JSON, and runs `scripts/update-runs-index.sh "$RUN_DIR"`:
   ```json
   {"from": "execute-plan", "to": "bureau-lite", "effective_from": "10",
    "at": "<log-append.sh --now>", "by": "robin", "reason": "<one line>"}
   ```
   `state.json#workflow` keeps the original id, so accounting and the eval still see what the
   run started as and can read the shift.
3. From unit 10 on, every unit gets its `risk-tags/<NN>.json` record and `RISK-TAGS:` line,
   and the close-out `REVIEW-COVERAGE:` line counts only units under the lite cadence, prefixed
   `from 10:`.

**Upshifting.** Moving back to every-unit review needs no permission: the Conductor, the
Delegate or Robin may do it at any unit boundary, for example after an `escalate` result or
when most units are firing anyway. Record it the same way with `"to"` set to the heavier
workflow's id (`execute-plan` for the every-prompt build tail) and `by` set to whoever made the
call.

## Done criteria

- `spec.md` and `plan.md` exist; `preflight-artifacts.sh --phase round1` and, at close-out,
  `--phase final` report no defects.
- `log.md` holds the design-model checkpoint with Robin's answer and exactly one Challenger
  design round with its adjudication.
- Every accepted unit has a `risk-tags/<NN>.json` record and a `RISK-TAGS:` line. Every unit
  whose result was review, error or escalate, and every REVIEW-ADD, has a Challenger verdict in
  `log.md` before its acceptance. Every waiver names the unit, the tag and Robin's words.
- An integration gate ran at each phase boundary, after each base-branch merge, and at the
  end, each with `integration-results.json` and a cold verdict.
- Build-tail step 7 is complete: terminal review paired with the green final gate, evidence
  published with the `REVIEW-COVERAGE:` line, merged to the dev/integration branch with a merge
  commit, worktree removed, `accounting.json` written.

## Edge cases

- **An escalate tag on a unit that is not really money or a destructive migration** (a
  `currency` field on a display formatter). Still a stop; Robin's keep-lite answer is the
  waiver, and the unit still gets its review. If it keeps happening, narrow the pattern by PR.
- **A unit flagged only by a test file** (a fixture token named `secret_value`). It gets the
  review. Test code that fakes credentials is where redaction and storage bugs hide.
- **Base-branch merge mid-run.** Take `UNIT_BASE` after the merge, or the range carries other
  people's changes and over-fires. The post-merge integration gate covers the merge itself.
- **Two parallel tracks in one worktree.** Their commits interleave; run the check on the union
  range and apply the result to both units. Over-firing is the safe direction.
- **Rename-only units.** The path check still sees both names; a moved `auth/` file fires
  `oauth-auth` without any line change. Review it: moves are where imports and guards drop.
- **A unit with no commits.** `risk-tags.sh` reports clean on an empty range. An empty unit is
  a build failure, not a clean unit; the Conductor's acceptance check catches it first.
- **No phases in `plan.md`.** The integration cadence falls back to every `every_n_prompts`
  accepted units (default 4).
- **Most units fire.** The run is paying full-cadence review anyway. Say so at the next phase
  gate and in the close-out summary so the eval can tell whether the forecast was wrong.

## Fallback behavior

- `risk-tags.sh` exits 2 (missing `python3`, an unresolvable ref, a bad config or project
  block): treat it as review, log it, and fix the cause before the next unit.
- The Challenger spawn fails: retry once fresh. If it fails again, the unit cannot be accepted;
  `[CHECKPOINT]`. A flagged unit is never accepted unreviewed.
- CodeRabbit is unavailable (exit 3): logged, as in the build tail. A clean unit is then
  accepted on the coder's checkpoint alone, and the coverage line says how many were.
- The Delegate's Conductor spawn fails at bootstrap: `agents/delegate.md § EC8`, unchanged.
- The task turns out to fail When NOT to use mid-build: upshift (§ Downshifting a running
  build) rather than finishing lite.

## Observability

- `log.md`: `RISK-TAGS:` per unit, `REVIEW-ADD:`, `RISK-TAGS waiver:`, `WORKFLOW-SHIFT:`, the
  Challenger SPAWN-EVENTs and verdicts, integration verdicts, and the close-out
  `REVIEW-COVERAGE:` line. All headings go through `scripts/log-append.sh`.
- `RUN_DIR/risk-tags/<NN>.json`: base and head SHAs, the config and project source used, files
  scanned and ignored, each fired tag with up to 20 hits (file, line, side, pattern).
- `state.json#workflow` and `#workflow_shifts`: what the run started as and every cadence
  change.
- `integration-results.json` per gate and `github/evidence.md` on the PR, which carries the
  coverage line for anyone reading the PR without the run dir.

The full agent specs, verdict format, worktree mechanics and checkpoint formats live in
`agents/orchestrator.md`, `agents/delegate.md` and the per-agent files. This file names the
sequence and the one place it differs from the build tail.
