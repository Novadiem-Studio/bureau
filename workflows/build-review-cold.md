# Workflow: build-review-cold

**When to use:** a self-contained change in existing code that you can just build — no fresh
requirements to settle, no plan to decompose — where you want the framework's speed-first third
gear: **build solo, then run ONE cold diff review only if the diff can fail silently.** This is the
right size for the common case where a bug would announce itself (a crash, a broken feature, a
visibly wrong result), so the only review worth paying for is the one that catches the bugs that
DON'T announce themselves. Most runs ship straight through the self-gate; the review fires only on
the ~10% of diffs that touch a silent-failure surface.

**When NOT to use:**
- A new product or feature that needs requirements or design before anyone can build → `feature`.
  This workflow has no spec/plan/prompt phase; if you can't just build it, it isn't this.
- A framework / canon change — anything touching `workflows/`, `agents/`, `docs/conventions*`, a
  `plans/` prompt folder, or `index.md` → the full pipeline / `execute-plan` with its gates. Canon
  changes carry the promotion + battle-test gate, which lives in the fuller review, not here.
- A diff touching MULTIPLE silent-failure surfaces at once, or a genuinely high-blast-radius change
  (a migration that also re-prices a ledger, an authz rewrite spanning a tenancy boundary) →
  escalate to `execute-plan` (or `feature` if it needs design). One cold reviewer on a wide,
  interacting diff is under-powered.
- A known defect to reproduce → repair → verify with a captured repro test → `bug-fix` (that
  workflow captures a repro and re-runs it; this one gates on the diff's failure surface instead).

This is the speed-first gear. Speed is the point, so the guard above matters: when a task fits two
workflows and one of them is this, take this ONLY if it clearly clears the four bars above.

**Type:** mixed (builds solo, then conditionally runs ONE cold review and adjudicates, in one run.
No `spec.md`, no `plan.md`, no `prompts.md`, no reconciliation, no per-diff critic loop.)

**Inputs:** the change to build (inline, or a short description); the target repo / sub-app; in
existing projects, the workspace orientation (see "Existing-project mode" in
`agents/orchestrator.md`) and the per-sub-app skills the affected surface needs. No plan doc, no
prompt folder.

**Outputs:** under `RUN_DIR` (see `docs/run-protocol.md`): `log.md`, `state.json`. When the
self-gate fires, `diff-context.md` — the diff + the one review question, handed to the cold
Challenger so it reviews cold (the diff, not the build session). The change itself lands as a diff
on the dev/integration branch (in a git worktree only if isolation was wanted). No `spec.md`, no
`plan.md`, no `prompts.md`.

**Leans on skills:** **novadiem-engineering** (cross-project coding standards — loaded by the
builder and, when it runs, the cold Challenger, so build and review hold the same bar) + the
project's `testing` skill if it has one + the per-sub-app skills the affected surface needs. Load
the skill; don't duplicate its runbook.

## Steps

Run these as spawned subagents where named (see "How to spawn an agent" and "Model routing" in
`agents/orchestrator.md`). Pass `RUN_DIR` as an absolute path in every spawn prompt.

1. **The Conductor** dispatches the coder the change's domain names — **The Mage** (frontend/UI) ·
   **The Systemsmith** (backend/data/contract) · **The Mechanic** (ops/infra) — at tier **strong**
   to plan and build the change solo and commit it: no spec/plan/prompts, no reconciliation, no
   per-diff critic loop, no worktree unless isolation is wanted → a built, committed diff on the
   dev/integration branch. Green-before-done still applies (`novadiem-engineering §5`): the builder
   runs the work's own checkpoint (type/tests/build) and gets it green. If the change turns out to
   need requirements or design, or spans several coders' domains at once, STOP and raise a
   `[CHECKPOINT]` — this isn't a build-review-cold task (see When NOT to use).

2. **Gate** — the silent-failure self-gate (advisory human judgment; the operator, or the Conductor
   self-gating — no script). Read the built diff and ask ONE question: **does this diff write
   durable state, move value, gate access, fire something irreversible, or change concurrent access
   to shared data — where a wrong result would NOT announce itself in use?** Scan ALL FIVE surfaces
   (do NOT stop at the first YES) and count how many fire, then route on the count: **0 fire, ship
   (step 3); exactly 1 fires, run the ONE cold build-diff review (step 4); 2 or more fire, or a single
   high-blast-radius change, escalate to fuller review (see When NOT to use).**
   - **S1 — Durable state:** a DB migration/schema change; a write to a persisted record, ledger
     row, or stored document; a change to how persisted data is serialized, keyed, or de-duplicated.
   - **S2 — Money / value:** code that computes, moves, credits, debits, prices, or reconciles a
     balance, ledger, invoice, quota, or credit.
   - **S3 — Auth / access / privacy:** a change to who can read/write what — an authz check, a
     permission/role gate, a visibility/scoping filter, a tenancy boundary, or a secret/PII path.
   - **S4 — Irreversible external action:** code that sends (email/SMS/webhook/notification),
     deletes, deploys, or mutates external infra (DNS, billing) where the effect can't be pulled back.
   - **S5 — Concurrency / race:** a diff that adds or changes concurrent access, shared mutable
     state, ordering assumptions, or a non-atomic read-modify-write on durable/shared data — where
     the failure is a lost update, double-processing (double-charge, duplicate send), or a dropped/
     reordered event. Cue: new locks/transactions/async ordering, or a shared-state write with no
     atomicity/idempotency guard on a durable or money surface.

     Decision test per surface: not "could the app be important" but "if this exact line is wrong,
     does something visibly break, or does it quietly do the wrong thing?" A crash / broken screen /
     wrong-but-visible number is self-announcing, so that surface does NOT fire. Silent corruption /
     silent leak / silent miscount / irreversible side effect / silent race fires. Scan all five and
     count: 0 fired, ship; exactly 1 fired, run the ONE cold review; 2 or more fired (or a single
     high-blast-radius change), do NOT run the single cold review, escalate (see When NOT to use),
     because the failure modes interact across surfaces and one refute-first reviewer under-powers it.
     `[CHECKPOINT]` if the operator can't decide the gate cleanly.

3. **The Conductor** (**strong**) — close-out path when the self-gate returned NO → `log.md`,
   `state.json`. Close out at the `[DEV-VERIFIED CHECKPOINT]` (format in `agents/orchestrator.md`):
   confirm dev is green, human go, then (if a worktree was used) merge to the dev/integration branch
   only and `run-worktree.sh remove`; append the run to `log.md`; run `scripts/account-run.sh <RUN_DIR>`
   and set `state.json#accounting` per `docs/run-accounting.md` as the final action. This is the
   common path. The run ends at dev-verified.

4. **The Challenger** (Critic, **strong**, fresh context required) — cold build-diff review, run only
   when the self-gate returned YES → `log.md`, findings. The Conductor first writes
   `RUN_DIR/diff-context.md` (the diff + the ONE question) and spawns ONE cold build-diff reviewer,
   refute-first, diff-only. It reviews per the build-diff slice (`agents/critic/build-diff.md`) and is
   spawned cold per the delegate-v2 cold-reviewer recipe (`docs/delegate-bridge/v2-integrated.md § v2 §3`):
   fresh context, `--tools "Read"`, `--add-dir "$CTX"` on the staged diff-context only,
   `--setting-sources ""` for coldness. It does **NOT** receive `log.md`, the build rationale, or the
   builder's reasoning. The one question it answers: **"what here corrupts, leaks, or miscounts
   WITHOUT announcing it?"** — adversarial, refute-first (assume a silent bug exists on the fired
   surface and try to find it).
   - **The Conductor / Robin adjudicates:** route the fix back to the coder (max 2x —
     `max_critic_loops`), accept, or `[CHECKPOINT]`. On a canon/process-surface diff, the spawn
     carries the `Promotion to canon: yes/no` block and the Challenger applies the 15a/15b promotion
     + battle-test gate (`agents/critic/build-diff.md`).
   - **Close out** at the `[DEV-VERIFIED CHECKPOINT]` as in step 3: human go, then (worktree merge +
     remove, if used), then append to `log.md`, then `scripts/account-run.sh <RUN_DIR>` last. The run
     ends at dev-verified.

> **Production boundary — hard stop (non-negotiable).** This workflow's finish line is the change
> **built, verified, and green on the dev/integration branch**. The Conductor does NOT deploy beyond
> dev, merge toward a release/prod branch, or ship to the public as part of this workflow. Same hard
> stop `workflows/execute-plan/build-tail.md` carries in full — see its "Production boundary — hard
> stop" block; not re-documented here at length. When dev is green, raise the
> `[DEV-VERIFIED CHECKPOINT]` and stop. Production is the human's call.

> **External-action boundary — separate gate (applies regardless of stage).** If the change fires
> any action in the external-action taxonomy (sent emails/SMS, chat posts, webhook calls,
> notifications, payment triggers, calendar invites, DNS/infra mutations, other side-effecting
> outbound HTTP), the builder must surface it and raise an `[EXTERNAL-ACTION CHECKPOINT]` before it
> fires — even at dev stage, and even if the self-gate would otherwise ship without a cold review.
> See `docs/external-action-boundary.md`. This gate and the production gate are separate
> protections; neither subsumes the other. (Note: firing an S4 irreversible external action fires
> BOTH the self-gate cold review AND this checkpoint.)

The full agent specs, verdict format, worktree mechanics, and checkpoint formats live in
`agents/orchestrator.md` and the per-agent files in `agents/`. This file just names the sequence; it
doesn't duplicate them.
