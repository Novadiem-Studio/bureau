## Review 2 — Prompts

Check for:
- **Hidden dependencies** — prompt N assumes something prompt N-1 doesn't produce
- **Scope bleed** — a prompt that's actually two or three prompts
- **Unreviewable diff shape** — a prompt likely to produce a sprawling or surprise diff,
  lacks a `Reviewability:` line, or mixes generated churn with authored code without naming it
- **Missing context** — a prompt that won't work without information not provided
- **Wrong sequence** — prompts that are ordered incorrectly
- **Untestable prompts** — no clear definition of what "done" looks like
- **Missing seam declaration** — any build prompt checkpoint that lacks
  `Seams under test:` (named public seam or explicit `none — <reason>`). For non-`none`
  seams, verify the prompt names `docs/conventions/tdd-seams.md` and asks the coder to
  mutation-verify the seam tests; bad seam choice is a Warning unless it makes the prompt
  untestable or leaves a load-bearing behavior unpinned.
- **Gap prompts** — phases of work that have no prompt covering them
- **Tooling ambiguity** — external-service work that fails to name the expected CLI, skill, MCP,
  docs source, or runbook when that choice matters for repeatability
- **Missing external-action gate** — in Review 2 you read `RUN_DIR/prompts.md` (a declared
  Review-2 input — fully in-contract). Apply two sub-checks against this 8-category taxonomy
  (inlined here because this slice must be self-contained):
    (a) any prompt describing an action in the external-action taxonomy without a corresponding
        `[EXTERNAL-ACTION CHECKPOINT]` is a **Blocker**;
    (b) for each external action that IS present in prompts.md and does carry an
        `[EXTERNAL-ACTION CHECKPOINT]` reference, verify the reference is present — a
        fired-able external action in a prompt with no checkpoint reference is a **Blocker**.

  1. **Email and SMS sends** — any outbound message to a real recipient address or phone number
  2. **Chat platform posts** — Slack, Discord, Teams, or equivalent outbound posts
  3. **Webhook calls to external URLs** — any POST/PUT/PATCH to a non-local URL that produces a side effect on the receiving system
  4. **Customer-facing notifications** — push notifications, in-app notifications, or equivalent outbound alerts to real end users
  5. **Payment triggers** — charge initiation, refund, or subscription modification
  6. **Calendar invites or event mutations** — any calendar event visible to or delivered to external participants
  7. **DNS and infrastructure mutations** — DNS record changes, domain transfers, firewall rule changes, or equivalent provider-side changes
  8. **Any other outbound HTTP to a non-local URL with a side effect** — the catch-all for actions not enumerated above but that produce an externally visible effect

  > RECIPROCAL SYNC NOTE: this inlined list duplicates the canonical taxonomy in
  > `docs/external-action-boundary.md`. If the taxonomy is edited in one file it must be
  > edited in the other. The canonical source is `docs/external-action-boundary.md`; this
  > copy is the enforcement fixture for the prompts review slice.

  Do NOT read `preflight.md` at any point in either review round — AC 16 (preflight PASS) is
  owned by the Conductor's workflow close-out, not a Challenger check.

  > DISAMBIGUATION — two boundaries, never double-flagged. The **production boundary** is the
  > existing "Production boundary — hard stop" block in
  > `workflows/execute-plan/build-tail.md`: deploy beyond dev, release promotion, public ship.
  > The **external-action boundary** is the 8-category taxonomy inlined in this slice:
  > outbound communications and externally visible side effects,
  > regardless of deployment stage. They are parallel protections for different risk classes.
  > Classify each finding as exactly ONE of the two — do NOT conflate them or double-label a
  > single finding as both.

- **Promotion gate — two-tier Blocker:** Apply this only when the spawn prompt declares a
  canon/process-surface review or `RUN_DIR/prompts.md` names target files that touch the surface
  list below. Both tiers key off the structured `Promotion to canon:` field in the spawn prompt,
  not a freeform string.

  **15a — Absence Blocker.** In Review 2, file-path evidence comes from the named target files
  in `RUN_DIR/prompts.md` (a declared Review-2 input — fully in-contract). If any prompt target
  touches a canon/process surface and the spawn prompt lacks the structured `Promotion to canon:
  yes/no` + `Reason:` block, that is a **Blocker**. Silence is not a pass; even an intended `no`
  must be explicit.

  The **canon/process surfaces** are (inlined here because this slice must be self-contained):

  - `workflows/` — any workflow file
  - `agents/` — any persona file
  - `docs/conventions.md`
  - `docs/conventions/`
  - `plans/` prompt folders (`NN-*.md` / `00-index.md`)
  - The spawn-prompt template in `agents/orchestrator.md` (the "How to spawn an agent" section)
  - `workflows/index.md`

  > RECIPROCAL SYNC NOTE: this inlined surface list duplicates the canonical surface list in
  > `docs/conductor-gates.md` (the "Declaring a canon/process-surface review" rule). If the
  > list is edited in one file it must be edited in the other. The canonical source is
  > `docs/conductor-gates.md`; this copy is the enforcement fixture for the prompts review
  > slice.

  **15b — Battle-test Blocker (fires only when the block reads `Promotion to canon: yes`).**
  When the structured block is present and declares `yes`, fire a **Blocker** when any of the
  following hold:

  (a) No `battle-test.md` exists beside the promoted artifact.

  (b) The matrix present does not contain at least one named edge case AND at least one named
  failure mode. A 3–5-case matrix composed entirely of happy-path variants — regardless of
  case count — is a **Blocker**.

  (c) A `waiver:` block is present but does not name BOTH the failing case AND the reason. A
  blank waiver (e.g. `waiver: accepted`) is itself a **Blocker**.

  (d) No `## Run` block exists in `battle-test.md`, OR its cases are not all
  pass-or-validly-waived. This is a **presence + results** check on the most recent `## Run`
  block — NOT a date comparison.

  A valid waiver (naming failing case + reason + Robin's explicit acceptance) closes 15b for
  that specific case only. The Challenger flags an inadequate waiver; it does NOT accept a
  waiver on Robin's behalf.
Write `RUN_DIR/verdicts/<attempt_id>.json` per `agents/critic.md § Verdict record` (`review_mode: prompts`; file-target modes only: hash each named `## Inputs` artifact fresh; diff-target modes bind the change set instead).
