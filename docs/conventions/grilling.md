# Grilling Discipline

> Canon module. Load this file for the initial Analyst pass in the `feature` workflow
> and when auditing a pre-spec grill checkpoint.

## Purpose

Grilling moves product facts and decision forks to the cheapest point in the run: before
Requirements are written. The Analyst walks the decision tree internally, looks up facts that
can be found in the project context or repo, and asks Robin for only the decisions that would
otherwise be guessed into the spec.

This adapts Matt Pocock's grilling pattern to the Bureau's async model: one batched checkpoint
with recommended defaults, not a live interview.

## Mechanical Qualification Trigger

The grill screen runs at the start of every `feature` workflow before `RUN_DIR/spec.md` exists.
The run qualifies for a pre-spec grill checkpoint when ANY of these signals fire:

1. **New surface:** the brief asks for a greenfield product, a new feature, a new user-facing
   surface, or a substantial behavior change, and does not name an existing shipped analog that
   this is merely extending.
2. **Material question count:** the Analyst finds three or more unresolved product questions
   whose answers would change requirements, scope, data shape, user flow, risk, or acceptance
   criteria.
3. **Unsourced user facts:** a load-bearing user fact is needed but not sourced from the brief,
   `project-context.md`, direct repo inspection, resolved grill answers, or a memory citation
   with provenance.
4. **High-blast-radius product call:** the brief touches auth or permissions, money or billing,
   external sends or publishing, durable retention/deletion/import, secrets or access, legal or
   privacy posture, or production-environment behavior.

The run skips the grill only when ALL of these are true: it is a small extension, bug fix, or
runbook-shaped operational change; there are two or fewer material product questions; no
load-bearing user fact is unsourced; and no high-blast-radius product call is present.

`open_questions_count` counts only material product decisions. Implementation details that the
Architect can decide later do not count.

## Auditable Trigger Line

The Analyst returns exactly one machine-readable trigger line to the Conductor before any
Requirements handoff:

```text
GRILL-TRIGGER: {"qualifies":true|false,"signals":["new-surface"|"material-question-count"|"unsourced-user-facts"|"high-blast-radius-product-call"],"open_questions_count":0,"user_facts":[{"fact":"<name>","status":"sourced|missing|assumed","source":"brief|project-context.md|repo:<path>|memory:<path>|resolved-grill|ASSUMED:<default>|none"}],"decision":"raise-checkpoint|skip|resolved-input","checkpoint_id":"grill|null","spec_exists_before":false}
```

Rules:

- `spec_exists_before` must be `false` for an initial grill. If `spec.md` already exists and
  this is not an explicit revision/resume after a resolved grill, the Conductor treats the run
  as out of order.
- `checkpoint_id` is `"grill"` only when `decision` is `"raise-checkpoint"`.
- A skip still returns the trigger line with `qualifies:false`, `decision:"skip"`, and the
  signals that were checked.
- After a resolved grill, the re-spawned Analyst returns `decision:"resolved-input"` and cites
  the resolved answers as a user source in Requirements.

## Checkpoint Shape

A qualifying initial pass writes no `spec.md`. The Analyst returns one `GRILL CHECKPOINT
REQUEST` block containing the trigger line and a numbered list of items.

Each item includes:

- the decision or fact to confirm;
- the source or inference that raised it;
- a recommended default;
- the impact if Robin changes the answer.

Every item must have a recommended default. If the Analyst cannot recommend a default, the item
is too under-specified for a routine grill and should be framed as a separate product fork using
the existing checkpoint/escalation path.

## User-Fact Provenance

User facts are facts about Robin, the user base, locale, operating context, or recipients that
the system would act on if accepted. The minimum list:

- timezone;
- locale or language;
- currency;
- country, region, legal jurisdiction, or tax context;
- person, organization, account, or customer identity;
- recipients, audience, or contact channel;
- date, time, schedule, cadence, or deadline;
- production target, environment, or deployment surface;
- external service, provider account, or integration tenant.

In Requirements, every load-bearing user fact must carry either `source:` or `ASSUMED default:`.
Valid sources are the project brief, `project-context.md`, direct repo evidence, a resolved grill
answer, or a memory citation with the memory fields required by the Analyst persona. If a fact is
not sourced and no safe default exists, it belongs in `### Open Questions`, not as a bare
assumption.

## Measurement

This mechanism ships as a measurement-pending discipline. The eval pass compares qualifying
runs against the Track 7 baseline: `rework_ratio` 0.22, one design-model correction caused by a
bare timezone assumption, and roughly 51 minutes of human checkpoint wait. Acceptance requires
net-positive evidence: rework saved must exceed the human wait added by the grill.
