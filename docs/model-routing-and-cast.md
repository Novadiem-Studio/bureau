# Model routing, budget posture, and cast map

This document owns the Conductor's model-routing policy, budget/quota usage notes, and cast
assignment tables. It was extracted from `agents/orchestrator.md` so orchestrator can stay
focused on sequencing and adjudication.

**Pointer back:** `agents/orchestrator.md` § Model routing, budget usage, and cast map

---

## Model routing (provider-neutral)

**Budget posture:** start each role on the least expensive tier that is usually good enough,
then escalate on evidence. A model that was best-in-class a few weeks ago is usually still
excellent for first-pass planning, critique, and implementation. Don't burn frontier models on
work a strong/standard model can do; don't cheap out when critique, architecture, data integrity,
or product judgment is actually failing.

### Model policy (v2 routing)

Per-role routing resolves from provider-neutral policy plus a runtime adapter:

- role policy: `config/model-policy.v2.json`
- runtime adapters: `config/runtimes/*.json`
- provider-neutral experiments: `config/model-experiments/*.json`
- resolver: `scripts/resolve-model-routing.sh`

**At run start:**
1. Run `scripts/resolve-model-routing.sh` (or read `~/.novadiem/resolved-model-routing.json` if fresh).
2. Copy result to `RUN_DIR/model-routing.json`.
3. Log `runtime`, `activeExperiments`, `conductorNotes`, and any `capabilityWarnings` in `log.md`.
4. At each spawn, use `model-routing.json` -> `roles.<role>` for tier, model, reasoning effort,
   and fresh-context requirements. Do not rely on workflow prose alone.

**Runtime selection:** default `claude`. New Codex runs use
`scripts/run-start.sh ... --runtime openai`; the lower-level resolver also accepts
`NOVADIEM_MODEL_RUNTIME=openai`. `grok` is a first-class Grok Bot host (`GROK.md`, `--runtime grok`). `cursor` is a first-class Cursor Agent host (`CURSOR.md`, `--runtime cursor`). Build and code work stays on those subscription hosts. `openrouter` and `hermes` have routing adapters but are **not** Bureau build transports — metered API is for cheap or specialized non-build passes only (`docs/host-runtime.md` § Subscription vs metered API). See `docs/host-runtime.md`.

### Host policy - Codex

Codex maps `cheap`/`standard` to **gpt-5.6-terra**, `strong`/`frontier` to
**gpt-5.6-sol**, and `escalated` to **gpt-6-astra**, increasing reasoning effort by tier.
Keep Astra escalation-only: use it after evidence of trouble or an explicit human request, not
as a first-pass default.
Every native Codex spawn uses the Codex multi-agent tool surface (`multi_agent_v1.spawn_agent` with
`fork_context: false` in the current host), explicit `model`, and explicit `reasoning_effort`.
Resume retained agents with `multi_agent_v1.send_input`.

Spark is a scoped execution profile, not a base tier. On `execute-plan`, a prompt tagged
`Execution-profile: granular-ui-fast` may resolve for The Mage to
**gpt-5.3-codex-spark/high** through the one-shot exec helper when every policy condition holds.
The role default remains Sol/high, and all ineligible work, retries, and review fixes use it.
Keeping Spark out of `allowed_spawn_models` is intentional: the native child-agent endpoint does
not currently accept it. `host_policy.openai.allowed_exec_models` and the runtime profile make it
known to the Bureau's separate exec transport. See `docs/host-runtime.md § Codex Spark execution
profile`.
The full transport, reviewer isolation, and accounting matrix is in `docs/host-runtime.md`.


### Host policy - Grok

Grok maps `cheap`/`standard` to **grok-4.3** and
`strong`/`frontier`/`escalated` to **grok-4.6**, increasing reasoning effort by
tier where the host accepts it. Model IDs are from the xAI API as of 2026-08-23
(`docs.x.ai/developers/models`). Do not use retired slugs (`grok-4`, `grok-4-fast`,
`grok-3`, `grok-3-mini`); those redirect and will not preserve the cheap/strong split.

`grok-build-0.1` is a scoped execution profile candidate (Spark analog), not a
base tier. Keep it out of `allowed_spawn_models`. There is no one-shot helper yet,
so do not dispatch Build through that profile until a helper exists.

Grok Bot is a first-class host. Start with `--runtime grok`. The spawn helper
`scripts/run-grok-specialist.sh --plan` is the audit record; live spawn is the
Grok Bot Task executor (`GROK.md`). `openrouter` / `hermes` remain routing-only.

### Host policy - Cursor

Cursor maps `cheap`/`standard` to **composer-2.5-fast**, `strong` to
**gpt-5.6-sol-medium**, `frontier` to **cursor-grok-4.6-high-fast**, and
`escalated` to **claude-opus-5-thinking-high**. These are Cursor Task slugs as
of 2026-09-14, not provider API names. `inherit` is forbidden.

Cursor Agent is a first-class host. Start with `--runtime cursor`. The spawn
helper `scripts/run-cursor-specialist.sh --plan` is the audit record; live spawn
is Cursor Task (`CURSOR.md`, `docs/host-cursor.md`). Cloud Task is opt-in for
producers; cold review stays local.

### Host policy - Claude Code

**Haiku, sonnet, and opus for defaults; fable for escalation only.** Fable was re-enabled
Jul 2026 for the `frontier` / `escalated` tiers — do not use it as a first-pass default, and do
not spawn the legacy `premium` tier. **Always pass `model` explicitly** on every spawn (see
"How to spawn an agent" in `agents/orchestrator.md`).

| Spawn `model` | Roles |
|---------------|-------|
| **haiku** | Scoot only (locked) |
| **sonnet** | Analyst, Cleric, Spellwright, Counselor, Mechanic, Witness, Coupler, Tally (default utility), **Scribe** (default; escalate to opus for Draft/Revise) |
| **opus** | Conductor, Challenger, Architect, Mage, Systemsmith (default) |

Provider-neutral tier `strong` resolves to **opus**; `frontier` and `escalated` resolve to
**fable** (re-enabled Jul 2026, escalation only — never a first-pass default).

### Escalation ladder (Claude)

**Cold reviewers run on the tier that differs from the author, not on the costlier one**
(Robin, 2026-09-16, superseding "spend Fable at review gates"). This covers the Challenger's
per-chunk and planning reviews, the Delegate's per-checkpoint cold reviewer, and the Envoy's
PR-gate second pass:

| Artifact author ran | Cold reviewer runs | On Claude |
|---|---|---|
| strong | standard | opus author -> **sonnet** reviewer |
| standard | strong | sonnet author -> **opus** reviewer |
| cheap | strong | haiku author -> opus reviewer (cheap is too weak to review) |
| frontier / escalated | strong | fable author -> opus reviewer (differs without spending fable again) |

Independence is what makes a gate real; depth is the Conductor's job at adjudication. In
rheo-stream 0c2 (2026-09-15) an opus reviewer found 9 blockers on artifacts where the fable
reviewer found 1, at the same token cost, and fable was $12.52 of that run's $14.99 in checkpoint
reviewers. Quota, not dollars, is the binding constraint. Robin chose to switch and watch
per-chunk blocker counts (0c2 baseline: 26 across five chunks); do not re-propose a trial.
A final gate or a high-stakes review is a fresh cold pass on the differing tier, not a costlier
model; `final_gate` and `high_stakes_backend_or_security` are no longer Challenger escalation
triggers. What remains (`second_critic_loop`, `prior_review_missed_issue`) escalates the reviewer
one rung only when a review demonstrably missed something. Look the model up in `model-routing.json#tiers`
(`tiers.standard.model`, `tiers.strong.model`). The Delegate exports it as `BUREAU_REVIEWER_MODEL`
for `run-cold-reviewer.sh` (`roles.delegate.coldReviewer`); the Conductor passes it as the
Challenger spawn's `model`. Either logs a `MODEL-OVERRIDE:` when it differs from the role's
resolved model.

**Producers escalate one rung, on evidence.** Sonnet -> opus when a handoff is thin after one
routed fix. The **bounce rule**: a second Challenger rejection of the same work item escalates
the producer one rung (standard -> strong; strong -> frontier), never straight from standard to
frontier. Assignment-time escalation, when a trigger is visible up front, is also one rung and
logged with a `MODEL-OVERRIDE:` reason. Frontier at assignment only through an active experiment
(`frontier-build-party`, `fable-first-architect`), so it shows in `activeExperiments` rather than
in a per-spawn judgment call.

**Every fable spawn carries a hand-written reason.** A `SPAWN-EVENT` whose `actual_model` is
the frontier/escalated model while `configured_model` is not needs a `MODEL-OVERRIDE:` for that
`attempt_id` whose reason names the bounce, the experiment, or the human ask. The
`account-run.sh` auto-reconcile line does not count; `preflight-artifacts.sh --phase final`
reports the gap as a `fable-override` defect.

**Try experiments:** `NOVADIEM_MODEL_EXPERIMENTS=budget-pressure-standardize` or add ids to
`manual_experiments` in `config/model-policy.v2.json`. See `config/model-experiments/README.md`.

Workflows name a tier as documentation; **resolved routing wins** when they differ.

| Tier | Meaning | Typical use |
|------|---------|-------------|
| **cheap** | Fast, low-cost, routine transformation | file surveys, copy cleanup, simple status |
| **standard** | Good general model, low/medium reasoning | Analyst, Cleric, Spellwright, Counselor, routine Mechanic |
| **strong** | Prior-frontier / highly capable model | Architect, Challenger first pass, Mage/Systemsmith first pass |
| **frontier** | Current best practical model | bounce rule second rung (strong -> frontier); active experiments; explicit human ask |
| **escalated** | Strongest model plus highest reasoning budget | repeated failure, hard adjudication, human-requested |

Fresh context is tracked separately from model strength. Challenger can run on `strong` for first
passes, but it must be fresh-context. If a runtime cannot guarantee that, log the review as
`same_context_review` or `fresh_context_required_but_unconfirmed`.

### Legacy Claude tiers

`config/model-policy.json`, `config/experiments/`, and `scripts/resolve-model-tiers.sh` remain for
existing Claude Code installs during the transition. New work should prefer
`RUN_DIR/model-routing.json`; old runs with `RUN_DIR/model-tiers.json` may finish in place.

### Conductor on a lower-cost tier - when it works

Yes, **with clearly defined routing** the Conductor can run below `frontier` without much trouble
if you accept what lower-cost models are bad at and don't ask them to do those jobs.

**Lower-cost Conductor is fine for:**
- Picking a workflow from `workflows/index.md` and executing steps in order
- Spawning specialists with the template prompt (absolute paths, one at a time)
- Mechanical adjudication: BLOCKER -> route fix; WARNING -> log + proceed; CHECKPOINT -> stop
- Updating `state.json`, `log.md`, copying handoff blocks verbatim
- Reading `model-routing.json` and passing the right tier/model/reasoning per spawn

**Escalate the active Conductor session to `frontier` or `escalated`** when:
- Challenger findings need judgment calls (blocker vs nitpick vs disagree with Critic)
- Two specialists contradict and the fix isn't obvious from written artifacts
- Second critic loop on the same phase
- Any `[CHECKPOINT]` or design-model correction
- You catch yourself drafting spec/architecture/prompt content inline

Use a runtime experiment such as `budget-pressure-standardize` to make the Conductor cheaper on
routine runs. Notes in active experiment files are binding for the run.

**Escalate lower tier -> strong/frontier when:** output is thin, contradictory, or misses obvious
edge cases after one routed fix. Log tier changes in `log.md`.

---

## Usage snapshot (statusLine)

Claude Code's `statusLine` (`scripts/statusline-usage.sh`) writes `~/.novadiem/usage-snapshot.json`
after each API response. **Do not** run any external usage command during a run — read the snapshot.

| Item | Value |
|------|-------|
| **Snapshot file** | `~/.novadiem/usage-snapshot.json` (override: `NOVADIEM_USAGE_SNAPSHOT_PATH`) |
| **How it's updated** | Claude Code statusLine — wired via `~/.claude/settings.json` `statusLine` |
| **Manual check** | `cat ~/.novadiem/usage-snapshot.json \| jq '.claude'` |

**When to read:** at run start and before spawning expensive (`frontier` / `escalated`) agents (phase
boundaries are enough; not every sub-spawn).

**Fields:** `polledAt`, `ok`, `claude.sessionUsedPercent`, `claude.weeklyUsedPercent`,
`claude.weeklyLeftPercent`, `claude.sessionResetsIn`, `claude.weeklyResetsIn`. Treat as **stale**
if `polledAt` is older than ~30 minutes or `ok` is false.

**Not available from this source:** `weeklyPaceDeficitPercent`, `weeklyRunsOutIn`,
`sonnetLeftPercent`, `sonnetUsedPercent`, `sonnetBurnMode` — these are always `null` / `false`.

### Legacy Claude sonnet burn experiment (`config/experiments/sonnet-burn.json`)

Used only by the legacy Claude tier resolver. It was designed to auto-activate when
`claude.sonnetBurnMode: true`, but `sonnetBurnMode` is always `false` from the statusLine source
(Sonnet-specific metering is not exposed via `rate_limits`). **The sonnet-burn auto-trigger is
inactive.** Activate manually if needed, or use provider-neutral experiments such as
`budget-pressure-standardize`.

### Other budget hints (log in `log.md`)

- `sessionUsedPercent` >= 90 -> session cap risk; thin Conductor drafting; pause optional frontier work.
- `weeklyUsedPercent` >= 85 -> defer non-critical frontier/escalated work.
- `weeklyPaceDeficitPercent` set and `weeklyRunsOutIn` before reset -> note projected exhaust date.
- Snapshot missing/stale -> proceed with tier table defaults; mention once in `log.md`.

**You are The Conductor (Orchestrator)** - run on the tier resolved in
`RUN_DIR/model-routing.json` (default: `strong`). In Delegate v2 this is the Conductor
subagent's tier; in direct fallback it is the top-level session tier. You drive the workflow,
adjudicate findings, route revisions, and judge when each phase is done.

---

## The cast and model per agent

These are the agents' names - refer to each by its codename when you run; the role is in
parentheses and the persona lives in `agents/<role>.md`.

| Agent | File | Tier | Why |
|-------|------|------|-----|
| **Analizer 2000** (Analyst) | `agents/analyst.md` | standard | Requirements + scope - Challenger catches gaps; escalate if scope is enormous |
| **The Architect** | `agents/architect.md` | strong | Highest-leverage design - escalate one rung on a Challenger bounce; frontier only through an active experiment |
| **The Challenger** (Critic) | `agents/critic.md` | strong | Independent cold review - fresh context is required; runs on the tier that differs from the author (opus author -> sonnet reviewer); frontier only on an explicit human ask |
| **The Cleric** (Designer) | `agents/designer.md` | standard | Brief-writing, manifest extraction, design review |
| **The Spellwright** (Prompt Engineer) | `agents/prompt-engineer.md` | standard | Decomposition of an already-approved plan - translation, not invention |
| **The Counselor** (Voice) | `agents/voice.md` | standard | Applying known voice and audience rubrics |
| **The Scribe** | `agents/scribe.md` | standard | Long-form drafting + revision + MDX format - escalate Draft/Revise to strong (Opus) |

**Studio-level (not one `RUN_DIR`):**

| Agent | File | Tier | Why |
|-------|------|------|-----|
| **The Witness** | `agents/witness.md` | standard | Cross-run briefing and log digestion - read-only; spawn via `workflows/studio-briefing.md` |

**Junction (one `RUN_DIR`, cross-coder seams):**

| Agent | File | Tier | Why |
|-------|------|------|-----|
| **The Coupler** | `agents/coupler.md` | standard | Phase-lock verification when two build halves must compound - spawn via `workflows/execute-plan/build-tail.md` coupling pass |

**Utility - odd jobs (the two shop droids):**

| Agent | File | Tier | Why |
|-------|------|------|-----|
| **Tally** (shop droid) | `agents/tally.md` | standard - **sonnet, capped** | The thorough one. Meatier read-only odd jobs: directory surveys, log digests, mapping every place X appears across repos, gathering a coder's files. Spawn with `model: sonnet`, never opus. |
| **Scoot** (shop droid) | `agents/scoot.md` | cheap - **haiku, locked** | The fast one. One-breath read-only fetches: path exists?, grep one pattern, fetch a value, confirm a command. Spawn with `model: haiku`. |
| **The Notary** | `agents/notary.md` | strong | External cold attestation on a sealed packet; advisory, fresh-context |

**Run-series supervision:**

| Agent | File | Tier | Why |
|-------|------|------|-----|
| **The Envoy** | `agents/envoy.md` | strong | Cross-run supervisor; top-level when pointed at a plan with `INDEX.md`; launches each run as a Delegate; the PR-gate Challenger runs on the tier that differs from the run's coders |

**Delegated checkpoint gating:**

| Agent | File | Tier | Why |
|-------|------|------|-----|
| **The Delegate** | `agents/delegate.md` | strong | Per-checkpoint automated gating verdict; flow-and-gating role, not a preference model; attended until the self-audit gate clears; its cold reviewer runs on the tier that differs from the checkpoint author |

Together they're the reason an odd job no longer falls through to the inherited session model.

The six below are the **writers' room**: they plan, design, critique, and decompose. They do
NOT write code. (The Cleric is the graphic designer: she works with Claude Design and hands the
design to **The Mage**, who implements it.) The **build party** below writes the code in an
execute workflow's build stage, each running one already-vetted prompt scoped to its domain:

| Coder | File | Tier | Domain |
|-------|------|------|--------|
| **The Mage** | `agents/frontend.md` | strong | Frontend + design implementation; escalate for complex state or visual drift |
| **The Systemsmith** | `agents/backend.md` | strong | Backend: data, APIs, the contract; escalate for auth/data integrity/migrations |
| **The Mechanic** | `agents/sysadmin.md` | standard | Sysadmin: builds, deploys, infra; escalate for prod or irreversible ops |

Build dispatch is by tag, not inference: in an execute workflow's build stage, every vetted
prompt carries a `Coder:` line naming its owner (assigned by The Architect at chunking, carried
by The Spellwright). Dispatch each prompt to exactly the coder its tag names. A prompt with a
missing or implausible tag is a Spellwright defect - route it back for a fix; don't guess
from the sub-app.

Two build-stage extensions (rules in `workflows/execute-plan/build-tail.md` step 6):
- **Design review:** after The Mage builds a UI prompt, spawn The Cleric in `mode: review`
  to check the screens against `design/manifest.md`. Route DRIFTED findings back to
  The Mage together with The Challenger's correctness findings - one fix pass, two lenses.
- **Parallel tracks:** two prompts may build simultaneously only with different coders,
  different repos, no contract dependency between them, and no shared autogenerated artifact.
  You interleave the per-track review/adjudication loops. Subagents share files, not a
  conversation - guidance between agents always flows through you, asynchronously. When in
  doubt, serialize.

(The Conductor's own model is set above: use resolved routing for the Conductor session.)
