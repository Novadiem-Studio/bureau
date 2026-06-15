---
priority: 05
status: idea (pre-spec)
suggested-workflow: feature
suggested-run-slug: per-run-accounting-ledger
---

# 05. Per-run accounting ledger (Tally + Ministry of Flow)

## One-liner
Every completed run produces a structured `accounting.json` packet; Tally gathers the data; Ministry of Flow surfaces cost, model mix, workflow efficiency, and a studio-wide trend.

## Problem
There is no durable answer to what a run cost — in passes, model tiers, or workflow efficiency. The data is scattered across `log.md`, `state.json`, `model-routing.json`, and usage snapshots. Ministry of Flow can show run status but not the economic shape of the work, so there is no feedback loop for sizing runs correctly.

## Idea
1. Define an `accounting.json` schema with confidence labels (`exact` / `estimated` / `inferred` / `unavailable`) for each field.
2. Add a close-out convention: every completed run produces an accounting packet beside its normal artifacts.
3. Add `scripts/account-run.sh` to read one `RUN_DIR` and emit the packet.
4. Give Tally a narrow read-only accounting prompt: gather facts from `log.md`, `state.json`, `model-routing.json`, and usage snapshots. Tally does not write the packet — the Conductor or the script does.
5. Add a Ministry of Flow reader for `accounting.json` and a studio-wide ledger (`output/studio/accounting-ledger.json`) that aggregates cost, model mix, workflow efficiency, and waste hints over time.

## Guardrails
Tally must remain narrow and read-only during the accounting pass — it is not a general writer. Confidence labels are mandatory; do not report bare numbers without a confidence label.

## Likely home
New `accounting.json` schema in `templates/`, `scripts/account-run.sh`, Tally persona extension in `agents/`, Ministry of Flow dashboard surface. Build via `feature` workflow.

## Done when
After a run completes, Robin can open Ministry of Flow and see: approximate cost or "unavailable" with a reason, role pass count, model tiers used, whether the workflow stayed appropriately sized, and a trend line across recent runs. `output/studio/accounting-ledger.json` exists and is populated by the close-out script.

## Open questions
- Should Tally own the accounting pass, or should the Conductor run it directly via the script?
- What is the minimum viable schema — which fields are worth tracking before usage APIs give exact token counts?
- Should the studio ledger live in `output/studio/` or alongside `output/runs/`?
