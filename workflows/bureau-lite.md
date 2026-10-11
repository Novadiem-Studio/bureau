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
build units), `log.md`, `state.json`, a `risk-tags/<NN>.json` record per build unit (plus
`<NN>+<k>.json` follow-ups for later commits), `integration-results.json` and
`risk-coverage.json` per integration gate, `github/` delivery evidence, `accounting.json`.
Optional: `prompts/` (coarse prompts, step 6) and `design/` (only when the plan names a UI that
needs a Claude Design pass). The change itself lands on the dev/integration branch through the
linked PR (or the recorded local fallback).

**Leans on skills:** **novadiem-engineering** (Architect, Challenger, every coder) + the
project's `testing` skill and per-sub-app skills. Scripts: `scripts/run-start.sh`,
`scripts/preflight-artifacts.sh`, `scripts/run-worktree.sh`, `scripts/pr-delivery.sh`,
`scripts/coderabbit-pass.sh`, `scripts/risk-tags.sh`, `scripts/risk-coverage.sh` and
`scripts/integration-gate.sh` (both run by the Delegate at gates), `scripts/terminal-pairing.sh`,
`scripts/account-run.sh`.

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

   The Conductor outputs the `[DESIGN-MODEL CHECKPOINT]` block exactly as
   `agents/orchestrator.md § Design-model checkpoint` specifies, then a second block headed
   `[BUREAU-LITE PLAN]` with the Analyst's open questions and their defaults, the phase list
   with unit counts, and the risk forecast rolled up per tag ("Phase 2: 6 units, 4 forecast to
   trip oauth-auth or tokens-secrets"). It reaches Robin the same way it does on a `feature`
   run, and only Robin answers it.
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
   `state.json` as usual. `run-worktree.sh create` records `state.json#git.base_sha`, the commit
   the run branch starts from. It is the anchor of the risk-tag record chain and the policy ref
   every scan reads the project's `risk_tags` block from, so nothing the run commits can change
   its own triggers.

8. **The Conductor** (**strong**) — build the units in order, 01..NN, through the build tail's step 6 with one substitution, and scan every commit with `risk-tags.sh` → `RUN_DIR/risk-tags/<NN>.json` per unit, `<NN>+<k>.json` per follow-up

   Everything in `workflows/execute-plan/build-tail.md` step 6 applies as written: the
   prior-fixture re-run gate and standing suite before every dispatch, the CI read between units
   on a GitHub-delivered run, `Coder:` tag dispatch, the coder's own green checkpoint in the
   foreground, the CodeRabbit pass and its dispositions, the Cleric review for UI units when a
   `design/manifest.md` exists, the review-size gate, fixture capture on accept, parallel-track
   limits, failure repair, and both boundaries. The substitution is the build tail's bullet
   "**The Challenger** cold-reviews that single diff". Under `bureau-lite` that review runs only
   when the risk-tag check says so. Per unit:

   a. Before dispatch, close the chain: if HEAD has moved past the head of the last record
      (an integration-gate fix, a Coupler fix, failure repair, a fix after a Challenger
      verdict), scan that range first as a follow-up of the last unit, `<last>+<k>`, and route
      it like a unit. A base-branch merge commit needs no record; the post-merge integration
      gate covers it. Then take `UNIT_BASE=$(git -C "$WORKTREE" rev-parse HEAD)`.
   b. The coder builds and commits; the checkpoint is green. Nothing may stay uncommitted:
      `risk-tags.sh` refuses a dirty worktree.
   c. The CodeRabbit pass runs and its dispositions are recorded (build tail step 6).
   d. Scan the unit's whole range, CodeRabbit fixes included:
      ```sh
      scripts/risk-tags.sh --worktree "$WORKTREE" --base "$UNIT_BASE" \
        --policy-ref "$(jq -r .git.base_sha "$RUN_DIR/state.json")" \
        --out "$RUN_DIR/risk-tags/<NN>.json"
      ```
      and log `RISK-TAGS: unit <NN> <result> [<tags>], record risk-tags/<NN>.json` with
      `scripts/log-append.sh`.
   e. Route on the exit code, never on a reading of the diff:
      - **0 clean:** the coder's tests and the CodeRabbit dispositions are the review. The
        Conductor adjudicates acceptance on those and the review-size gate.
      - **1 review:** step 9 runs on this unit before it can be accepted.
      - **2 error:** fail closed, step 9 runs. If the cause is a dirty tree, a wrong base, the
        config or the project block, fix it and re-scan; the re-scan replaces the record.
      - **3 escalate:** stop dispatching. Return a `genuine-fork` (signal 6) naming the unit,
        the tag and the record path. Robin either upshifts the run (§ Downshifting a running
        build, last part) or keeps it lite. Either way this unit gets step 9. A keep-lite answer
        is logged as `RISK-TAGS waiver: unit <NN> <tag>; by Robin: "<Robin's words>"`.
   f. If fix commits land after the scan (a Challenger `revise`, a review-size reroute), scan
      them as `<NN>+<k>` before accepting the unit; a flagged follow-up needs its own step 9
      read.
   g. The Conductor may add a review the script did not ask for: log
      `REVIEW-ADD: unit <NN>: <one-line reason>` and run step 9. It may never skip one the
      script asked for.
   h. A risky change the patterns missed (found by an integration gate, the terminal review, or
      a REVIEW-ADD) is a failure signature (`docs/conventions/failure-signatures.md`). The build
      tail's failure-repair rule promotes the fix into a durable artifact: a pattern in the
      project's `risk_tags` block, or a PR to `config/risk-tags.json`.

9. **The Challenger** (Critic, build-diff, **strong**, fresh context required) — cold review of one flagged unit or follow-up → `log.md`, findings

   Only for records step 8 sent here. Spawned cold per the build-diff slice
   (`agents/critic/build-diff.md`) and the cold-reviewer recipe
   (`docs/delegate-bridge/v2-integrated.md § v2 §3`), with SPAWN-EVENT `attempt_id`
   `challenger-unit-<NN>-<n>` (n counts reviews of that unit). `risk-coverage.sh` matches
   reviews to records by that id and by time, so use it exactly. The Challenger gets the
   record's diff, the unit brief from `plan.md` (or its prompt), the risk-tag record and the
   dispositioned CodeRabbit findings file. It does not get `log.md` or the coder's reasoning.
   Its question: **"on the surfaces these tags name, what here corrupts, leaks, miscounts or
   fires WITHOUT announcing it?"**, plus scope against the unit brief. **The Conductor
   adjudicates**: accept, route the fix back to the coder (max 2, `max_critic_loops`), or
   `[CHECKPOINT]`.

10. **Gate** — integration checkpoints at phase boundaries, after any base-branch merge, and the final gate, plus the coverage check. `[CHECKPOINT]`

    The Conductor returns `routine-checkpoint` with `checkpoint-subtype: integration` and the
    right `gate-point` after the last accepted unit of each phase (`docs/conductor-gates.md §
    Integration checkpoint cadence (build runs)`), with the question naming
    `risk-coverage.json`. The Delegate runs `integration-gate.sh` as on any build run, and also
    runs the coverage check itself, since the build does not grade its own homework:
    ```sh
    scripts/risk-coverage.sh "$RUN_DIR" --out "$CTX/risk-coverage.json"
    ```
    It stages `risk-coverage.json` in the cold reviewer's packet as a supplementary artifact
    (`agents/delegate.md` § Main manager loop, step 3). A result other than `covered` (a gap, a
    record scanned with a different tag list or policy ref, or a flagged record with no
    `challenger-unit-<NN>` review after it) is a Blocker for that checkpoint: the reviewer
    returns `revise` naming it. Accepting a unit is never a checkpoint, so the Delegate's cold
    reviews in this workflow happen at these integration gates and the terminal review.

11. **The Conductor** (**strong**) — close out through build-tail step 7, plus the coverage gate → `log.md`, `state.json`, `github/evidence.md`, `accounting.json`

    Fixture promotion, the terminal whole-PR cold review paired with a green final gate on the
    same head SHA (`scripts/terminal-pairing.sh`), the close-out gates (preflight PASS,
    external-action log, `docs-sync-needed`, `lessons-append`), merge by the resolved delivery
    path (a merge commit, never a squash), worktree removal, and `account-run.sh` last. Added:
    - **Coverage gate (Blocker):** `scripts/risk-coverage.sh "$RUN_DIR"` exits 0 on the final
      head before the evidence is published. Log its `REVIEW-COVERAGE:` line verbatim and copy
      it into `github/evidence.md`. The line comes from the script, never typed.
    - `scripts/preflight-artifacts.sh "$RUN_DIR" --phase final` reports no defects.

> **Production boundary and external-action boundary.** Both apply exactly as in
> `workflows/execute-plan/build-tail.md` ("Production boundary — hard stop" and
> "External-action boundary — separate gate"). A unit that trips `external-irreversible` gets
> its cold review AND still raises the `[EXTERNAL-ACTION CHECKPOINT]` before anything fires.
> The risk tags never replace either gate.

## Risk tags

`config/risk-tags.json` is the authoritative list and `scripts/risk-tags.sh` applies it. Each
tag matches changed file paths and changed (added or removed) lines with case-insensitive
patterns, over the commits `base..head`. Prose files, lockfiles and binary assets are skipped,
except agent, skill and instruction files (`.claude/**`, `SKILL.md`, `agents/*.md`,
`CLAUDE.md`, `AGENTS.md` and siblings) and `project-context.md`, which are always scanned. The
record names files, line numbers and the pattern that matched, never the line text, since a
flagged line may hold a secret.

| Tag | Class | Covers |
|---|---|---|
| `oauth-auth` | review | OAuth flows, auth callbacks, PKCE/CSRF/JWT, authn/authz checks, `middleware.*`, tenant and owner filters |
| `tokens-secrets` | review | token storage, secret store, credentials, API and private keys, crypto, cookies and web storage, `.env*` |
| `network-egress` | review | server-side outbound HTTP/sockets (Python, Node, Go, absolute-URL `fetch`), webhooks, host/origin allowlists, CORS |
| `tool-allowlist` | review | agent tool allowlists and `tools:` frontmatter, `.claude/settings*.json`, MCP server config, permission modes |
| `redaction` | review | redaction, PII scrubbing, masking, log/print calls that carry tokens or secrets |
| `durable-state` | review | additive migrations and DDL (SQL, Alembic, Rails, Django, Prisma schema) |
| `external-irreversible` | review | email/SMS/chat sends, DNS/infra mutation, deploys, force pushes, PR merges, publishes, recursive and object-store deletes |
| `concurrency` | review | locks, transactions, idempotency and dedup, thread/process pools, schedulers, cron and launchd |
| `risk-policy` | review | any change to `project-context.md` or `config/risk-tags.json` |
| `money` | escalate | payments, payouts, refunds, invoices, ledgers, billing, card charges |
| `destructive-migration` | escalate | drop/rename/truncate/delete/update-set, Django `RemoveField`/`RunPython`, inside migration or SQL files |

The first five are the set Robin chose on the upwork-collector run. The rest overlap
`build-review-cold`'s silent-failure surfaces S1-S5, but a pattern list catches only part of
what that gate's human judgement does: persisted-record writes, serialization and keying
changes, and visibility filters outside the named idioms are not matched. Those reach a review
through the Conductor's REVIEW-ADD, the integration gates and the terminal review.

One cold reviewer per flagged unit, however many tags fire. `build-review-cold` escalates when
two or more surfaces fire because its single review is the only one the change ever gets. Here
the unit already sits inside a design the Challenger has read, and every unit is read again at
its phase gate and in the terminal whole-PR review. A credential unit that trips `oauth-auth`,
`tokens-secrets` and `network-egress` together is the normal case for this workflow, not an
outlier; the review question names every fired tag.

A project adds to the list with one block in `project-context.md`, committed on the base branch
before the run starts. `risk-tags.sh` reads it from `state.json#git.base_sha` (`--policy-ref`),
so a run cannot change its own triggers, and any edit to `project-context.md` during the run
trips `risk-policy`:

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
not set `ignore_paths`, lower a class, narrow a default tag with `line_scope`, or carry two
blocks; any of those makes the script exit 2 (fail closed). Changing a default pattern is a PR
to `config/risk-tags.json` with a regression fixture, like any other script change.

The tags are a floor. Over-firing costs one cold review; under-firing is the failure the
workflow exists to prevent, so a noisy pattern gets narrowed by PR, never by skipping reviews
in a run.

## Selecting bureau-lite at run start

- Robin names it, or triage picks it per `workflows/index.md` after checking every When NOT to
  use bar. Log the triage line as usual, naming the bar that was closest.
- `scripts/run-start.sh <RUN_DIR> --target <repo> --workflow bureau-lite` writes
  `state.json#workflow: "bureau-lite"` and `workflow_shifts: []`. The Delegate bootstrap passes
  the same id when it spawns the Conductor.
- If `project-context.md` holds a `risk_tags` block, the Conductor notes it in `log.md` at run
  start, so the extra triggers are visible before the first unit.

## Downshifting a running build

An `execute-plan` or `design-build` build, or a `feature` run that has continued into the
execute-plan build tail, can move to this cadence. Only Robin can make that call, by telling the
top-level session (the Delegate, or the Conductor in direct mode). The Conductor or the Delegate
may suggest it in a checkpoint relay ("12 of 25 prompts left, 3 forecast to touch credential
code"), but neither applies it on its own.

**When it takes effect.** At the next unit boundary during the build. The prompt in flight
finishes under the old cadence, including any Challenger review already started, and reviews
already run stand. A shift requested while the run is still planning takes effect at the next
planning step instead, and drops the planning steps this workflow does not have
(reconciliation, a second design round, the Spellwright and the prompts Challenger round when
the plan already has units).

**What changes.** From `effective_from` on, step 8's per-unit routing replaces the build tail's
every-prompt Challenger, and step 10's coverage check joins each integration gate. Existing
prompts become the units, in order; their `Coder:` tags stand. Integration gates, CodeRabbit,
fixtures, the terminal review and both boundaries do not change. `preflight-artifacts.sh`
treats a missing prompts artifact as acceptable once a shift to `bureau-lite` is recorded.

**What gets recorded, in order:**

1. The top-level session logs Robin's instruction with a real clock read, then relays it to the
   Conductor on the next resume:
   ```sh
   scripts/log-append.sh "$RUN_DIR" "WORKFLOW-SHIFT: execute-plan to bureau-lite from unit 10" - <<'EOF'
   by: Robin, "<Robin's words, verbatim>"
   effective_from: 10   (09 finishes under the old cadence)
   changes: per-prompt Challenger only on records risk-tags.sh flags; coverage check at gates
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
   `state.json#workflow` keeps the original id, so the runs index and accounting still show
   what the run started as. No script reads the shift for accounting yet; it is there for the
   eval and for `risk-coverage.sh`, which anchors its chain at the base of unit
   `effective_from`'s record.
3. From unit 10 on, every unit gets its records and `RISK-TAGS:` lines, scanned with
   `--policy-ref` set to `state.json#git.base_sha`. A run created before `base_sha` existed
   uses `git merge-base <base_branch> HEAD`, computed once at the shift and passed unchanged
   to every scan.

**Upshifting.** Moving back to every-unit review needs no permission: the Conductor, the
Delegate or Robin may do it at any unit boundary, for example after an `escalate` result or
when most units are firing anyway. Record it the same way, with `"to"` set to the heavier
workflow's id (`execute-plan` for the every-prompt build tail) and `by` set to whoever made the
call.

**What is not machine-checked.** That a waiver or a downshift really came from Robin. Both are
written by the session he spoke to, never by the Conductor on its own account, and both carry
his words verbatim; nothing verifies the authorship. Escalate waivers at least arrive as the
answer to a `genuine-fork`, which only Robin answers.

## Done criteria

- `spec.md` and `plan.md` exist; `preflight-artifacts.sh --phase round1` and, at close-out,
  `--phase final` report no defects.
- `log.md` holds the design-model checkpoint with Robin's answer and exactly one Challenger
  design round with its adjudication.
- `scripts/risk-coverage.sh "$RUN_DIR"` exits 0 on the final head: every commit since the
  anchor sits in a record scanned with the default tag list and the run's policy ref, and every
  flagged record has a `challenger-unit-<NN>` review after it (or, for a `review` record only,
  Robin's waiver). Its `REVIEW-COVERAGE:` line is in `log.md` and `github/evidence.md`.
- An integration gate ran at each phase boundary, after each base-branch merge, and at the
  end, each with `integration-results.json`, `risk-coverage.json` and a cold verdict.
- Build-tail step 7 is complete: terminal review paired with the green final gate, evidence
  published, merged to the dev/integration branch with a merge commit, worktree removed,
  `accounting.json` written.

## Edge cases

- **An escalate tag on a unit that is not really money or a destructive migration.** Still a
  stop; Robin's keep-lite answer is the waiver, and the unit still gets its review. If it keeps
  happening, narrow the pattern by PR.
- **A unit flagged only by a test file** (a fixture token named `secret_value`). It gets the
  review. Test code that fakes credentials is where redaction and storage bugs hide.
- **Base-branch merge mid-run.** Take `UNIT_BASE` after the merge. The merge commit itself
  needs no record (the chain check allows merge-only gaps); the post-merge integration gate
  covers it.
- **A rewritten history** (a reset or rebase past an accepted unit). `risk-tags.sh` refuses a
  base that is not an ancestor of head, and the chain check reports the orphaned records.
- **Uncommitted or untracked files.** `risk-tags.sh` exits 2 until they are committed or
  removed, so nothing reaches a merge unscanned.
- **Two parallel tracks in one worktree.** Their commits interleave; scan the union range once
  and give both units that record (or a follow-up each). Over-firing is the safe direction.
- **Rename-only units.** The path check sees both names; a moved `auth/` file fires
  `oauth-auth` without any line change. Review it: moves are where imports and guards drop.
- **No phases in `plan.md`.** The integration cadence falls back to every `every_n_prompts`
  accepted units (default 4).
- **Most units fire.** The run is paying full-cadence review anyway. Say so at the next phase
  gate and in the close-out summary so the eval can tell whether the forecast was wrong.

## Fallback behavior

- `risk-tags.sh` exits 2 (no `python3` or `git`, a dirty tree, a non-ancestor or empty range,
  a bad config or project block, any internal error): treat it as review, log it, fix the cause
  and re-scan.
- `risk-coverage.sh` exits 1 at a gate: route the named gap or missing review to the Conductor
  (scan the gap, run the missing review) before the gate can pass. Exit 2 (no `base_sha`, no
  worktree, an unreadable record): fix the setup; the gate does not pass on an unrun check.
- The Challenger spawn fails: retry once fresh. If it fails again, the unit cannot be accepted;
  `[CHECKPOINT]`. A flagged record is never accepted unreviewed.
- CodeRabbit is unavailable (exit 3): logged, as in the build tail. A clean unit is then
  accepted on the coder's checkpoint alone; say how many were in the close-out summary.
- The Delegate's Conductor spawn fails at bootstrap: `agents/delegate.md § EC8`, unchanged.
- The task turns out to fail When NOT to use mid-build: upshift (§ Downshifting a running
  build) rather than finishing lite.

## Observability

- `log.md`: `RISK-TAGS:` per record, `REVIEW-ADD:`, `RISK-TAGS waiver:`, `WORKFLOW-SHIFT:`, the
  Challenger SPAWN-EVENTs (`challenger-unit-<NN>-<n>`) and verdicts, integration verdicts, and
  the close-out `REVIEW-COVERAGE:` line from `risk-coverage.sh`. Headings go through
  `scripts/log-append.sh`.
- `RUN_DIR/risk-tags/<NN>.json` and `<NN>+<k>.json`: base and head SHAs, commit count, scan
  time, config sha256, policy ref and project source, files scanned and ignored, each fired tag
  with up to 20 hits (file, line, side, pattern).
- `RUN_DIR/checkpoints/<NN>-context/risk-coverage.json` per integration gate: the chain, every
  unit's records and results, and each problem found.
- `state.json#workflow`, `#workflow_shifts` and `#git.base_sha`: what the run started as, every
  cadence change, and the anchor.
- `integration-results.json` per gate and `github/evidence.md` on the PR, which carries the
  coverage line for anyone reading the PR without the run dir.

The full agent specs, verdict format, worktree mechanics and checkpoint formats live in
`agents/orchestrator.md`, `agents/delegate.md` and the per-agent files. This file names the
sequence and the places it differs from the build tail.
