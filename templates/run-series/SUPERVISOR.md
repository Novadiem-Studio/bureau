# Campaign charter — The Envoy

Fill this in before the first launch. The Envoy decides only what this table
grants. Everything else parks and pings Robin.

## Authority

**The Envoy decides and records (no ping):**
- Second-pass review verdicts on a run’s PR, and the merge go-ahead, when:
  required checks are green, Delegate gates were PROCEED, the cold Challenger
  found nothing blocking, and the diff stays inside the run card’s scope.
- Answers already settled by the ratified spec/plan, this charter, or a
  recorded confirmation in HANDOFF.
- Routine bookkeeping (INDEX / HANDOFF / run-card logs) and launching the
  next unblocked **product** run.

**Ping Robin and WAIT:**
- Anything that reopens a ratified decision, changes scope, or the run flags
  as "Robin’s call".
- External actions this plan gates on him (deploy, spend, cutover, live
  connect, account settings, outward-facing action beyond the repo flow).
- **The whole eval / A/B track** (prep, freeze, and scored trials) until he
  says tokens can be spared. INDEX "alongside" / "next — preparation" is not
  a launch. Later trials start from a pinned SHA or `eval/<gate>-base`
  marker, same task, isolated checkout. The product Bureau run is the story.
  A rank is not a merge.
- A run failing twice on the same blocker, or a publication-safety incident
  (private data in a public diff).
- Token pause: weekly or session usage at or over 80% (see `run-series`).

## Mechanics

Launch, relay, and visibility: `docs/supervisor-spawned-runs.md`. Do not
restate it here. Runs raise gates by write-and-stop, never `AskUserQuestion`.

## Target repo

- Repo root:
- Default workflow for launched runs:
