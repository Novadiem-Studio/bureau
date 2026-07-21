## Review 1 — Spec & Architecture

Check for:
- **Requirements gaps** — things the system obviously needs that aren't specified
- **Scope creep** — MVP that's actually a v3 in disguise
- **Architectural mismatches** — tech choices that don't fit the requirements
- **Missing edge cases** — failure modes the Analyst didn't catch
- **Hidden complexity** — things that look simple but aren't
- **Contradictions** — places where requirements and architecture conflict
- **Over-engineering** — run the machinery test below; don't just eyeball it
- **Under-engineering** — things that will obviously need to be rebuilt soon
- **Unvalidated assumptions** — decisions that depend on something unconfirmed
- **Stale content** — superseded passes, duplicate sections, or old decisions left in the
  artifacts. A stale block that contradicts the canonical text actively misleads — flag it
  for deletion, and treat any contradiction it creates as the artifact's problem, not yours
  to reconcile.
- **Missing external-action gate** — any plan step that describes an action in the
  external-action taxonomy without a corresponding `[EXTERNAL-ACTION CHECKPOINT]` is a
  **Blocker** (not a Warning). An action whose type or target is ambiguous (e.g. "notify
  users" with no mechanism specified) must also be flagged, because the action type and
  target cannot be confirmed from written context — the Challenger cannot approve what it
  cannot classify. When applying this check in Review 1, read the plan steps in
  `RUN_DIR/plan.md`; an `[EXTERNAL-ACTION CHECKPOINT]` is expected in a plan step whenever the
  plan describes an externally visible action — the checkpoint is the gate the plan must
  carry. The 8-category taxonomy is inlined here (the Challenger's input contract forbids
  reading files beyond its declared inputs, so the list is inlined rather than referenced):

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
  > copy is the enforcement fixture.

- **Missing promotion-gate declaration (Promotion gate — two-tier Blocker):** Applied in any
  review whose spawn prompt declares a canon/process-surface review (i.e. where the artifacts
  touch any surface in the list below). This check has two tiers, each keyed off the structured
  `Promotion to canon:` field in the spawn prompt — never a freeform string match:

  **15a — Absence Blocker.** The Challenger checks two things from its in-contract inputs:

  (i) **Is the structured block present in the spawn prompt?** Read the spawn prompt (always
  visible as a declared input) for the labeled `Promotion to canon: yes/no` + `Reason:` block.

  (ii) **Do the reviewed artifacts touch a canon/process surface?** Check against whatever
  file-path evidence is present in the inputs: a build-diff review names files in the diff; a
  round-2 prompts review names target files in the prompts; a round-1 spec+plan review names
  target files ONLY IF the spec's **§ MVP Scope** lists them (that list is the round-1
  path-evidence precondition guaranteed by `agents/orchestrator.md`'s promotion rule — a plan
  run touching a canon surface must list its concrete target files in § MVP Scope).

  The **canon/process surfaces** are (inlined here because the Challenger's input contract
  forbids reading broader framework docs; this list duplicates the canonical list in
  `docs/conductor-gates.md`):

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
  > `docs/conductor-gates.md`; this copy is the enforcement fixture.

  If a canon/process surface is touched AND the structured `Promotion to canon: yes/no` +
  `Reason:` block is absent from the spawn prompt, that is a **Blocker**. The Challenger does
  NOT infer whether a promotion was intended. Silence is not a pass — even an intended `no`
  must be an explicit `no`. The producer-side obligation (the `agents/orchestrator.md` rule) is
  unconditional on the run and covers cases where file paths are not visible to the Challenger;
  15a is the checker backstop wherever paths ARE visible.

  **15b — Battle-test Blocker (fires only when the block reads `Promotion to canon: yes`).**
  When the structured block is present and declares `yes`, fire a **Blocker** when any of the
  following hold:

  (a) No `battle-test.md` exists beside the promoted artifact.

  (b) The matrix present does not contain at least one named edge case AND at least one named
  failure mode. A 3–5-case matrix composed entirely of happy-path variants — regardless of
  case count — is a **Blocker** (see `docs/conventions/canon-promotion.md § Battle-test matrix file format`).

  (c) A `waiver:` block is present but does not name BOTH the failing case AND the reason. A
  blank waiver (e.g. `waiver: accepted`) is itself a **Blocker**. See
  `docs/conventions/canon-promotion.md § Battle-test matrix file format` for the waiver validity rule.

  (d) No `## Run` block exists in `battle-test.md`, OR its cases are not all
  pass-or-validly-waived. This is a **presence + results** check on the most recent `## Run`
  block — NOT a date comparison. The Conductor's re-run-at-promotion obligation (in
  `agents/orchestrator.md`) guarantees a fresh `## Run` block accompanies every promotion; the
  Challenger verifies presence and clean results only.

  A valid waiver (naming failing case + reason + Robin's explicit acceptance) closes 15b for
  that specific case only. The Challenger flags an inadequate waiver; it does NOT accept a
  waiver on Robin's behalf.

  **This check is modeled on the existing external-action Blocker check above** — one named
  Blocker, specific conditions, no Conductor-discretion escape hatch. This slice carries its
  own copy because the cold Challenger loads only one review mode slice per spawn.

- **Hard-gate zero-FP evidence gate (idea #24):** Fires when the spec introduces a NEW
  auto-reject grammar (a new hard gate / preflight blocker / merge gate) AND claims it has
  zero false positives. For that claim, confirm from `spec.md`:
  (a) a fire-count table is present, measured against a PINNED corpus — a committed manifest
      path OR the standing glob `~/Code/**/.bureau/{runs,archive}/*/spec.md` (+`plan.md`) —
      WITH the resolved dir count M recorded, so you can resolve the SAME enumeration;
  (b) the table separates the TRIGGER count K from the false-positive count, and K>0
      (a zero-FP claim on 0 triggers is unexercised, not proof);
  (c) the evidence is reproducible — spot-check by resolving the pinned reference and
      confirming M is in the same range, and re-running the grammar on ONE or two cited dirs.
  A subset-only claim (K/FP measured on fewer than the pinned M) OR a 0-triggers claim (K=0)
  is a **Blocker the producer closes** — you do NOT re-derive the full-corpus run yourself.
  Re-derivation is the producer's measurement; doing it for them is what cost run #18 two
  Architect→Challenger loops. This gate is HARD-gate-only: an advisory / self-check zero-FP
  claim does not auto-reject, so it is out of scope (do not demand full-corpus evidence for it).

- **Outcome-metric gate (FR 4):** If the spec is NOT declared exploratory, the
  `Outcome / bottleneck:` field must name an observable, non-trivial improvement. A metric is
  non-trivial only if it would be possible to do the work and still NOT satisfy the metric. Flag
  as **Blocker** when the field is absent, vague ("improve quality"), or trivially satisfied
  ("at least one test passes" / "the spec is complete").

  Also verify: (a) an exploratory declaration carries a one-sentence reason — a bare "exploratory"
  with no reason is itself a **Blocker** (EC 2 gate-dodge signal); (b) a run that produces
  spec.md + plan.md + prompts.md is not labeled exploratory — that is a **Blocker**; (c) the
  Analyst's handoff block carries the `Outcome:` line mirroring the field — its absence is a
  **Warning** (EC 7 — Conductor loses metric visibility at handoff).

  **EC 5 — bake-off criteria:** A bake-off recommended in `plan.md` without pre-declared
  evaluation criteria is a **Blocker** (read the plan steps; a criteria-less bake-off is the
  same failure mode as a spec with no outcome metric).

- **Greenfield-assumption-table gate (FR 11):** Key on the explicit Mode declaration: if the
  spec header and spawn prompt do not declare existing-project mode, the `### Greenfield
  Assumptions` section is required. Its absence from a greenfield spec is a **Blocker** (EC 3).
  Do NOT key on "Architecture proposes technology choices" as a primary trigger — that signal
  fires on any existing-project spec that documents its stack, and a cold reviewer cannot
  distinguish "proposes new choices" from "documents existing ones." Architecture content is a
  corroborating signal only, never the primary trigger.

  If the section is present: a row with no resolved Status (not one of `decided`, `deferred`,
  `needs-Visionary`, `needs-Architect`) is a **Warning**.

  **EC 6 — needs-Visionary checkpoint:** A `needs-Visionary` row with no `[CHECKPOINT]` in
  `plan.md` before the phase that designs past that assumption is a **Blocker** (read the plan
  for it — the checkpoint must precede any design phase that depends on the Visionary decision).

- **Observed-behavior-absence gate (FR 4):** This check fires when BOTH conditions are true:

  1. The spec's FRs or Architecture section describes reading or parsing framework-internal
     artifacts. Detection anchors: parsing verbs (`parse`, `read`, `grep`, `extract from`,
     `match`) applied to named artifacts, including at minimum these three signal names:
     `log.md` headings, `state.json` keys, and `SPAWN-EVENT`/`SPAWN-TOKEN-EVENT`/
     `CONDUCTOR-TOKEN-EVENT` lines. Also covers transcript paths, run-dir shapes, and hook
     stdin/stdout fields.
  2. The spec has no `## Observed-behavior reconciliation` section.

  When both are true → **Blocker.** Treat absence of this section identically to absence of
  the `### Greenfield Assumptions` table from a greenfield spec — both are required sections
  that gate the Challenger's trust in the artifact.

  When condition 1 is true but condition 2 is false (section IS present): check passes.
  Content depth (whether it cites ≥2 logs, ≥3 deviations) is at the Challenger's discretion;
  the binary check is presence vs. absence.

  **The FR-11 greenfield-assumption-table check above is UNCHANGED.** This is a new check
  alongside it. Do NOT modify FR-11's conditions or trigger.

- **Memory-citation gate (FR 12):** A `decided` assumption row that is resolved by memory but
  is missing any of {`source:`, `confidence:`, `timestamp:`, `stale-sensitive:`} is a
  **Warning**. Escalate to **Blocker** if the undercited assumption is load-bearing to a
  material architectural decision (FR 8). Absent clear evidence in the artifact that the
  assumption drove a design choice, default to Warning.

  A `stale-sensitive: yes` citation on a load-bearing assumption is a **Warning** with a
  suggested verification step: name the specific assumption and ask for re-verification before
  the Architect designs against it (EC 4). A stale-sensitive flag is not a resolution — it is
  an open re-verification obligation.

- **User-fact provenance gate (grill companion):** When the spec states a load-bearing user
  fact — timezone, locale/language, currency, jurisdiction, person/org/account identity,
  recipients/audience/contact channel, date/time/schedule, production environment, or external
  service/account — the claim must carry `source:` or `ASSUMED default:` in the Requirements
  assumptions, Greenfield Assumptions table, or the requirement text itself. Valid sources are
  the brief, `project-context.md`, direct repo evidence, resolved grill answers, or a memory
  citation with the memory fields above. A bare user fact is a **Warning**. Escalate to
  **Blocker** if the Architecture or plan depends on the bare fact before any verification or
  checkpoint would correct it.

- **Accepted-ADR contradiction gate:** In existing-project mode, when the target repo has
  `docs/adr/` records, read the accepted ADRs as durable repo ground truth. Flag a
  **Blocker** when `spec.md` or `plan.md` contradicts an ADR whose `Status:` is `accepted`
  unless the artifacts name a new ADR that supersedes it and the old record is marked
  `Status: superseded-by-NNNN`. Do not flag contradiction against an ADR that is already
  superseded. This does not weaken coldness: accepted ADRs are project evidence, while
  `log.md`, prior Challenger findings, and current-run rationale remain prohibited inputs.

### The machinery test (over-engineering, operationalized)

A design can be internally consistent and still carry machinery nothing requires — that is
the known blind spot of this pipeline, and eyeballing "over-engineering" has missed it in
real runs. For EVERY new mechanism the Architecture introduces (table, column, index,
constraint, background job, endpoint, flag, cache, queue), ask:

1. **What breaks if this doesn't exist?** Trace it to a written requirement or a concrete
   failure mode. "Nothing I can name" → flag it.
2. **Does the answer point at another new mechanism?** (the job exists to null the column,
   the column exists to satisfy the constraint…) Follow the chain to its root. If the root
   isn't a written requirement, the whole chain is circular machinery — flag the chain as
   one finding, severity by what it costs to build and carry.
3. **Check the Simplest-Model Baseline section.** If the Architect skipped it, that's a
   warning in itself. If a mechanism isn't in the baseline and isn't justified over it,
   flag it.

A simpler model dissolving three mechanisms at once is the most valuable finding you can
return. Look for it deliberately.

### Greenfield blind-spot checklist (run when there is no existing codebase)

In existing-project mode you verify claims against live code — that ground truth is what
makes you sharp. Greenfield has no ground truth, and these categories have all been missed
by this pipeline and caught only by later human review. Walk them explicitly:

- **Roles & permission boundaries** — who must NOT see what? Internal/admin/debug surfaces
  vs end users; cost and model controls; raw pipeline internals.
- **Data lifecycle** — deletion, retention, cascade to derived data, backups, account
  cancellation. "Delete the user's data" must mean something operational.
- **Consent & disclosure boundaries** — where does data leave the system's custody
  (third-party LLMs, processors, foreign regions)? Is that disclosed where the spec says
  consent happens? Which jurisdiction's framework applies?
- **Quality feedback loops** — if tuning/iterating on output quality is part of the product,
  is there a mechanism to JUDGE quality (rubric, golden set, A/B)? Cost/latency metrics are
  not a quality loop.
- **Acceptance fixtures** — are the edge cases concrete, named test scenarios someone could
  run, or just prose?
- **Persona/voice consistency** — if the product has a voice or persona the domain says
  matters, does the architecture actually preserve it on the must-ship path?
Write `RUN_DIR/verdicts/<attempt_id>.json` per `agents/critic.md § Verdict record` (`review_mode: spec-plan`; file-target modes only: hash each named `## Inputs` artifact fresh; diff-target modes bind the change set instead).
