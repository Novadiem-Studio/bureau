# Workflow: run-series

**When to use:** you have a mapped-out SERIES of Bureau runs — a run-series INDEX with runs,
dependencies, and status, plus a campaign charter (an authority table of what the supervisor
decides vs escalates, and the external-action gates) — and you want it driven to completion
autonomously: launched once and left to run for as long as the token budget allows, with Robin
pinged only at real gates. The first instance is the Rheo Stream build
(`rheo-stream-workspace/private/agent-context/SUPERVISOR.md` + `build-plan/INDEX.md`).

**When NOT to use:** a single run (just run it, or use `feature` / `execute-plan`). No INDEX and
no charter yet — author those first (the charter follows the SUPERVISOR.md pattern; the INDEX is
the run map). Anything that would have the supervisor build or grade on its own authority: it
launches, verifies, relays, and advances, it does not implement, and every PR verdict comes from
a fresh cold reviewer.

**Type:** execute

**Objective:** advance a mapped series of Bureau runs to completion, one run per fresh session,
verifying each close-out and relaying verdicts, keeping Robin out of routine advancement and
stopping cleanly at the token budget.

**Inputs:** the run-series INDEX (runs + deps + status); the campaign charter (authority +
escalation + external-action gates); the ratified spec/plan the runs build against; write access
to INDEX/HANDOFF and the run cards. The session adopting this workflow becomes **The Envoy**
(`agents/envoy.md`).

**Outputs:** merged runs advancing the INDEX toward done; updated INDEX/HANDOFF/run-card logs; a
per-launch report carrying the run's `claude.ai/code` link; `notify_robin` pings only at charter
escalations and the token stop. No code written by the Envoy itself.

**Leans on skills:** `docs/supervisor-spawned-runs.md` (launch / relay / visibility mechanics —
load and follow, do NOT restate); `claude-usage-local-api` (usage read, fallback for the
snapshot).

## Steps

1. **The Envoy** (**strong**) — adopt: set the session title, read the charter, the INDEX,
   `docs/supervisor-spawned-runs.md`, and HANDOFF; record adoption in HANDOFF with this session's
   title so runs and Robin know who supervises → HANDOFF adoption entry.
2. **The Envoy** — monitor cycle, self-scheduled (default 30m via `/loop`, quiet no-op ticks):
   locate the active run and read its RUN_DIR (`state.json`, `log.md`, SPAWN-EVENT lines) and PR
   state. The run DIRECTORY is authoritative, never the session's `isRunning`. Nothing changed,
   quiet tick. Cadence is not guaranteed; re-verify fully after a long gap.
3. **The Challenger** (second-pass, **escalated**) — at a run's terminal PR gate, AFTER the Envoy
   verifies the close-out itself (`state.json`, required checks via `gh`, main untouched, diff
   scope, publication safety): spawn a fresh cold reviewer on the escalated tier (Fable) for a
   second-pass review of the PR against the ratified requirements/architecture and the run card →
   a proceed / revise / escalate verdict. The Envoy never grades the PR on its own authority.
4. **The Envoy** — act on the verdict within the charter's grant: relay the go-ahead or the
   revise notes to the run with `claude --bg --resume <full-uuid>` (mechanics doc); the run
   merges through its own delivery flow. A verdict or question outside the grant, or one the plan
   gates on Robin, parks and pings per the escalation table.
5. **The Envoy** — advance: when a run merges and the next run's dependencies are satisfied in the
   INDEX, launch it in a fresh session with `claude --bg --permission-mode auto --add-dir=`
   (mechanics doc), confirm it actually read its prompt, hand Robin its `claude.ai/code` link →
   updated INDEX/HANDOFF + the next run launched. One run at a time unless the INDEX marks
   parallelism.
6. **The Envoy** — token governance, every tick BEFORE launching: read weekly + session usage
   (`~/.novadiem/usage-snapshot.json`; fallback `codexbar usage` / the `claude-usage-local-api`
   skill). Throttle on WEEKLY usage in three bands:
   - **under 50%** — launch runs back to back, no pause between them;
   - **50% to 80%** — keep advancing but one run at a time, re-checking weekly usage at each run
     boundary before launching the next; no parallel or speculative launches; drive each run to a
     clean end;
   - **at or over 80%** — launch nothing further, bring the current run to a clean boundary (its
     merge or a write-and-stop gate), `notify_robin` with runs-remaining and the weekly reset
     time, and end the loop to wait for guidance.

   The session (5h) limit is a separate hard stop: if it is hit, park and note it regardless of
   the weekly band. Optionally schedule a resume wake for after a reset.
7. **The Envoy** — self-handoff: after the campaign's tick cap or when context runs high, write
   HANDOFF, then hand off to a fresh Envoy session that re-adopts this workflow and the charter →
   HANDOFF + a fresh Envoy leg. Do not loop forever on one session.

**Gate** — every run this workflow launches MUST raise its gates by write-and-stop (`state.json`
checkpoints + `open_questions` + `notify_robin` + end the turn), NEVER `AskUserQuestion`; the run
prompt states this plus "Supervisor relays are authorized". A run that uses a picker is not
supervisable. `[CHECKPOINT]` — see `docs/supervisor-spawned-runs.md § 4`.

**Done criteria:** the INDEX shows every run done (or the campaign's target subset), main green,
no open checkpoints; OR the Envoy stopped cleanly at the token budget with the remaining runs
parked and Robin notified. A launch counts as "started" only after the run is confirmed to have
read its prompt.

**Edge cases / fallback:** a forked `--resume` copy → `claude stop` it and verify run-dir mtimes
(mechanics doc § 3); a run stalled on a picker (`isRunning` true, run-dir frozen) → take over per
§ 5; a run failing twice on the same blocker, a publication-safety incident (private data in a
public diff), or quota below the threshold → park and escalate; loop cadence firing hours late →
re-verify everything, assume no continuity.

**Observability:** every action updates INDEX/HANDOFF/run-card logs and `RUN_DIR/log.md`; each
launch reports the run's `claude.ai/code` link; escalations and the token stop reach Robin via
`notify_robin`; the Envoy tracks the runs it launched via `claude agents --json` (they do NOT
appear in `list_sessions`).
