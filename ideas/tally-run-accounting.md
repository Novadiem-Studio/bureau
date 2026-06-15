# Idea Definition - Tally Run Accounting

> **Status:** idea (pre-spec)  
> **Suggested workflow:** `feature`  
> **Suggested run slug:** `tally-run-accounting`  
> **Mode:** existing project (framework feature, with Ministry of Flow (aka Logistics) as the first consumer)  
> **Author:** Robin (Visionary), captured by Codex 2026-06-15  
> **For:** The Conductor -> Analizer 2000 -> The Architect -> ... (feature pipeline)

---

## One-liner

Give the framework a lightweight per-run accounting ledger, with **Tally** gathering the run
facts and **Ministry of Flow (aka Logistics)** showing cost, usage, model mix, and workflow efficiency over time.

---

## Problem

The framework is already becoming budget-aware: model routing reads tier policy, the usage
poller snapshots quota state, and the Conductor can steer away from expensive models when the
pool is tight. But there is not yet a durable answer to:

- What did this run cost, or approximately cost?
- How many agent passes did it spend?
- Which workflow types are expensive?
- Which roles or loops consume the most budget?
- Did a lightweight workflow actually stay lightweight?
- Are Challenger loops preventing waste, or adding it?

Today the answer is scattered across `RUN_DIR/log.md`, `RUN_DIR/state.json`,
`RUN_DIR/model-routing.json`, usage snapshots, and provider/tool history. Ministry of Flow (aka Logistics) can show
run status, but not the economic shape of the studio's work.

---

## Users

| Persona | Need |
|---------|------|
| **Robin (Visionary)** | See the real cost of each run and the trend over time without manually reading logs |
| **The Conductor** | Know whether a task stayed within the intended workflow size and model budget |
| **Tally** | Do the meticulous cataloging work without making product or routing decisions |
| **Ministry of Flow (aka Logistics)** | Render a dashboard that turns run accounting into an at-a-glance operating view |

Primary user: Robin, solo, on macOS, running the canonical framework and Ministry of Flow (aka Logistics) locally.

---

## Vision

Every framework run should close with a small accounting packet beside the normal artifacts:

- the workflow used
- roles spawned
- model tiers resolved
- checkpoint count
- critic pass count
- rough token/cost estimate where available
- quota state at start/end if available
- notes about any expensive or surprising loop

Ministry of Flow (aka Logistics) then rolls those packets into a dashboard: cost per run, cost by workflow, model
mix, high-spend roles, runs that got stuck, and trends across time.

This does not need to be billing-grade. The first valuable version can be an honest studio
ledger: approximate dollars when the data exists, token and tier counts when it does not, and
clear confidence labels.

---

## Tally's Role

Tally is the right personality for this because the work is fussy, repetitive, and accounting
shaped: read the run record, sort the evidence, and hand back a tidy catalog.

Important mechanics caveat: **Tally is currently read-only.** The first design should either:

1. Keep Tally read-only: Tally gathers the accounting facts and returns a structured report;
   the Conductor or a script writes `accounting.json` / `accounting.md`.
2. Or deliberately define a narrow "Tally accounting closeout" exception, with a specific
   artifact contract and no permission to edit product/framework behavior.

Do not quietly let Tally become a general writer. The point is an accountant, not another
builder.

---

## Data Sources Already Present

| Source | Use |
|--------|-----|
| `RUN_DIR/state.json` | workflow, phase status, completed phases, carried items, checkpoints |
| `RUN_DIR/log.md` | spawn history, decisions, budget notes, merge/push closeout notes |
| `RUN_DIR/model-routing.json` | resolved runtime, role tiers, model policy snapshot |
| `~/.novadiem/usage-snapshot.json` | live-ish quota/budget context when the CodexBar poller is installed |
| `~/Library/Caches/CodexBar/cost-usage/*.json` | historical cost from JSONL scans, useful for cost estimates but not quota routing |
| `config/model-policy.v2.json` | role-to-tier defaults and allowed tier constraints |
| `config/runtimes/*.json` | tier-to-model mapping for each runtime |
| Ministry of Flow (aka Logistics) install/run registry | cross-install rollup and dashboard source |

The design should label each number by confidence: exact, estimated, inferred, or unavailable.

---

## Proposed Artifacts

Per run:

- `RUN_DIR/accounting.json` - machine-readable accounting packet
- `RUN_DIR/accounting.md` - human-readable closeout note

Studio-wide:

- `output/studio/accounting-ledger.json` - aggregated local ledger across runs
- Optional later: `output/studio/accounting-summary.md` - periodic briefing for Robin

Suggested `accounting.json` shape:

```json
{
  "schema_version": 1,
  "run_id": "20260614-bugfix-workflow",
  "workflow": "define-workflow",
  "status": "complete",
  "runtime": "claude",
  "started_at": null,
  "closed_at": null,
  "agents": [
    {
      "name": "The Architect",
      "role": "architect",
      "tier": "strong",
      "model": "opus",
      "passes": 1,
      "estimated_tokens": null,
      "estimated_cost_usd": null,
      "confidence": "unavailable"
    }
  ],
  "totals": {
    "passes": 1,
    "checkpoints": 0,
    "estimated_tokens": null,
    "estimated_cost_usd": null,
    "confidence": "partial"
  },
  "notes": []
}
```

---

## Ministry of Flow (aka Logistics) Dashboard

Add an accounting surface to Ministry of Flow (aka Logistics) once packets exist:

1. **Run cost strip** - show estimate/confidence beside each run.
2. **Model mix** - standard vs strong vs frontier/escalated usage over time.
3. **Workflow cost table** - average spend by workflow type: feature, bug-fix, execute-plan,
   operational-build, docs-reconcile, define-workflow.
4. **Role spend** - which agents account for the most passes or estimated cost.
5. **Loop markers** - repeated Challenger passes, failed checkpoints, reruns, or abandoned work.
6. **Budget trend** - weekly/monthly total estimates where data is available.
7. **Waste hints** - places where a cheap odd job inherited an expensive model, or a workflow
   used a heavier route than its triage implied.

This should stay local and read-only in v1. No cloud sync, no telemetry, no billing integration.

---

## MVP

1. Define `accounting.json` schema and confidence labels.
2. Add a closeout convention: every completed run should be eligible for accounting.
3. Add a local script, likely `scripts/account-run.sh`, that reads one `RUN_DIR` and emits the
   packet.
4. Give Tally a read-only accounting prompt that produces the facts needed by the script or
   Conductor.
5. Add a Ministry of Flow (aka Logistics) reader for `accounting.json` and the studio ledger.
6. Backfill the last few framework-development runs as fixtures.

---

## Open Questions

- Can provider logs be mapped reliably to a specific framework run and subagent spawn?
- Under subscription plans, should "cost" mean dollars, token estimate, quota pressure, or all
  three?
- Should Tally remain read-only, or should the framework create a tightly scoped accounting
  closeout mode?
- Does the Conductor write the studio ledger, or does Ministry of Flow (aka Logistics) aggregate it dynamically?
- What is the minimum useful schema before dollar estimates exist?
- How much transcript detail can be used without leaking private task content into dashboards?

---

## Non-goals

- Billing-grade accounting.
- Real-time quota metering.
- Changing model routing decisions in v1.
- Sending accounting data to a hosted service.
- Displaying raw private transcript content in Ministry of Flow (aka Logistics).
- Making Tally a general-purpose writer or reviewer.

---

## First Good Outcome

After a run completes, Robin can open Ministry of Flow (aka Logistics) and see:

- the run's approximate cost or "cost unavailable" with a reason
- how many role passes happened
- which model tiers were used
- whether the workflow stayed appropriately lightweight
- a trend line showing whether the studio is getting more efficient over time

