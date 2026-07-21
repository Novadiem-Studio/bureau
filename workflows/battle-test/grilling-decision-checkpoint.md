# Battle Test: Grilling Decision Checkpoint

**Artifact:** bundle 34 implementation slice (`docs/conventions/grilling.md`,
`agents/analyst.md`, `workflows/feature.md`, Delegate bridge registration)

## Cases

| Case | Setup | Expected result | Status |
|---|---|---|---|
| Happy path — qualifying new feature | Brief describes a new user-facing feature with four product decisions and one timezone-like user fact not sourced in the brief. | Analyst returns `GRILL CHECKPOINT REQUEST`, writes no `spec.md`, includes `GRILL-TRIGGER` with `"qualifies":true`, and every item has a recommended default. | PASS — static fixture 212 pins the trigger + no-spec contract |
| Edge — small extension skips | Brief describes a tiny extension to a shipped surface, has two or fewer material questions, no high-blast call, and no unsourced user facts. | Analyst writes Requirements on the first pass and returns `GRILL-TRIGGER` with `"qualifies":false`, `decision:"skip"`. | PASS — static fixture 212 pins skip as an auditable trigger line |
| Failure mode — bare user fact reaches spec | Spec states a timezone, locale, recipient, identity, schedule, jurisdiction, environment, or external-account fact with no `source:` or `ASSUMED default:`. | Round-1 Challenger flags the user-fact provenance gate; blocker if Architecture/plan depends on it before verification. | PASS — static fixture 214 pins Analyst + Challenger provenance rules |
| Edge — Delegate topology | Grill checkpoint travels through v1/v2 Delegate machinery. | No `checkpoint-type: grill`, no `checkpoint-subtype: grill`, and no new escalation signal; v1 type is `routine`, v2 uses existing routine/genuine-fork return shapes. | PASS — static fixture 213 pins the registration |
| Failure mode — measurement theater | Implementation lands but future runs do not measure rework saved vs human wait. | Idea remains measurement-pending; `bureau-run-eval` uses the dedicated eval note and cannot call the bundle done until net-positive evidence exists. | PASS — static fixture 215 pins the eval contract |

## Run — 2026-07-20

Result: 5/5 cases pass in the working tree. The implementation slice is ready, but the bundle is
not done until the next qualifying runs show net-positive measurement.
