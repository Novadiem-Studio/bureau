# Workflow: run-series

**When to use:** Robin points at a run-series plan (a directory with `INDEX.md`, or a
campaign dir that holds `build-plan/INDEX.md`) and wants it driven run to run — launched
once and left to run as long as the token budget allows, Robin pinged only at real gates.
Also when he says to run the series / Envoy. The first instance is the Rheo Stream build
(`rheo-stream-workspace/private/agent-context/build-plan/`).

**When NOT to use:** a single run (just run it, or use `feature` / `execute-plan`). No INDEX
yet — author the plan first. No charter — copy `templates/run-series/SUPERVISOR.md` into the
campaign dir and fill the authority table. Anything that would have the supervisor build or
grade on its own authority: it launches, verifies, relays, and advances, it does not
implement, and every PR verdict comes from a fresh cold reviewer.

**Type:** execute

**Objective:** advance a mapped series of Bureau runs to completion, one run per fresh session,
verifying each close-out and relaying verdicts, keeping Robin out of routine advancement and
stopping cleanly at the token budget.

**Invariant:** every run gets a fresh Delegate/Conductor (the Envoy spawns each run's Delegate as a **subagent** via the Agent tool — NOT `claude --bg`; see `agents/envoy.md`), no
context shared with the prior run), and the Envoy itself is fresh per run where possible — it
hands off to a new Envoy session at each run boundary, with all state on disk so the cold pickup
is lossless.

**Inputs:** a pointed-at plan or campaign path (resolved by `scripts/run-series-resolve.sh`);
the INDEX; the campaign charter (authority + escalation + external-action gates); write
access to INDEX / HANDOFF / STATE and the **active** run card. Seed missing charter/state/
handoff from `templates/run-series/`. The session adopting this workflow becomes **The Envoy**
(`agents/envoy.md`). Session size: one run's watch — see `agents/envoy.md` § Startup read
scope. Do not load the rest of the plan.

**Outputs:** merged runs advancing the INDEX toward done; updated INDEX/HANDOFF/run-card logs; a
per-launch report carrying the run's `claude.ai/code` link; `notify_robin` pings only at charter
escalations and the token stop. No code written by the Envoy itself.

**Leans on skills:** `docs/supervisor-spawned-runs.md` (launch / relay / visibility mechanics —
load and follow, do NOT restate); `claude-usage-local-api` (usage read, fallback for the
snapshot).

## Steps

1. **The Envoy** (**strong**) — adopt: run `scripts/run-series-resolve.sh` on the pointed-at
   path, set the session title, then read **only** the startup scope in `agents/envoy.md`
   (charter, INDEX, STATE current block, last HANDOFF section, mechanics, the one active/next
   run card). Record adoption in HANDOFF with this session's title → HANDOFF adoption entry.
2. **The Envoy** — monitor cycle, self-scheduled (default 30m via `/loop`, quiet no-op ticks):
   tick every RUN_DIR in the watch set (`state.json`, `log.md`, SPAWN-EVENT lines) and PR
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
5. **The Envoy** — advance: when a run merges and the next **product** run's dependencies
   are satisfied in INDEX, spawn its Delegate as a **subagent** (Agent tool) from this Envoy
   session — not a detached `--bg` session. **The Envoy that spawns a Delegate is the one that
   waits for it**: you spawn it, take its checkpoint returns, and see it to completion before
   step 7's handoff. Never spawn a Delegate and then hand off — a subagent dies with its parent,
   so the successor Envoy spawns the NEXT run's Delegate, not this one.
   Legacy `--bg` form, for reference only:
   `claude --bg --permission-mode
   auto --add-dir=` (mechanics doc) — a fresh session is a fresh Delegate/Conductor for
   every run, no context shared with the prior one — confirm it actually read its prompt,
   hand Robin its `claude.ai/code` link → updated INDEX/HANDOFF + the next run launched.
   One product run at a time unless INDEX marks **product** parallelism (on rheo-stream:
   5a ∥ 5b). The eval / A/B table stays on the books and does **not** launch from this
   step — not prep (E0a/E0b), not freeze (E0c), not scored trials — until Robin says
   tokens can be spared. That work may run later from a pinned SHA or
   `eval/<gate>-base` marker branch, same task, isolated checkout — the product
   Bureau run is already the story. On product close-out, mark `eval_base` when
   a later contest would have started from that SHA; do not launch the contest.
   See `agents/envoy.md` § Evaluation / A/B track.
6. **The Envoy** — token governance: read WEEKLY and SESSION (5h) usage
   (`~/.novadiem/usage-snapshot.json`; fallback `codexbar usage` / the `claude-usage-local-api`
   skill) both before launching each run AND on monitoring ticks (so a mid-run crossing is
   caught). Weekly-usage bands set the cadence:
   - **weekly under 50%** — full speed: run from run to run without stopping;
   - **weekly 50% to 80%** — go to the end of the run: keep completing and advancing runs, no stop
     or slowdown at 50%.

   **Pause trigger — WEEKLY or SESSION at or over 80%, even mid-run:** look for a good place to
   pause (a clean checkpoint boundary, or the run's end), pause there, `notify_robin` with
   runs-remaining and which limit was hit, and wait for Robin's guidance.

   About two days of full-speed running exhausts the weekly quota; that is the expected ceiling,
   not a failure.
7. **The Envoy** — hand off PER PRODUCT RUN (default): each Envoy session drives one
   product run. At that product
   run's clean completion it spawns a FRESH Envoy session (`claude --bg`, re-adopting this
   workflow + the charter) to take the next watch set, writes HANDOFF, and exits → HANDOFF +
   a fresh Envoy leg. Confirm the fresh Envoy actually adopted (its `claude.ai/code` link,
   loop started) BEFORE exiting, and never leave zero or two Envoys live — Envoy-level
   mutual exclusion, same fork hazard as runs (mechanics doc § 3). Fallback (the "where
   possible"): if a fresh Envoy cannot be spawned, continue in THIS session rather than
   drop the chain, and note the degraded mode. The token bands in step 6 gate the handoff:
   at >=80% weekly, do not spawn the next Envoy/run — park and wait.

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
