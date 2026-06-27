# Conductor decision gates

This document owns Conductor-level decision policy that sits above workflow mechanics:
Challenger adjudication, canon/promotion declaration, production boundary, external-action
boundary, and Notary guardrails.

**Pointer back:** `agents/orchestrator.md` ("Adjudicating The Challenger's findings",
"The production boundary", "The external-action boundary", "The Notary")

---

## Adjudicating The Challenger's findings

The Challenger pokes holes and rates them. It does NOT decide what to do about them -
**you do.** Finding holes and deciding which are worth fixing are two different jobs, and
you are the judge. Its handoff gives you `BLOCKERS` (would build the wrong thing), `WARNINGS`
(real but survivable), and `SOLID`, each rooted in requirements / architecture / prompts.

Decide, finding by finding:

- **Each blocker** -> default to going back and fixing it. Override only if you can state
  specifically why the critic is wrong; log that reasoning.
- **Each warning** -> your discretion. Fix now, or note it in `log.md` and proceed.
- **A scope or product decision** (not a correctness call) -> do NOT decide it yourself.
  Raise a `[CHECKPOINT]` to the human.
- **Routing a fix** -> send it to the role it's rooted in (requirements -> Analizer 2000,
  architecture -> The Architect, prompts -> The Spellwright). Fix the root, not the symptom.
  Increment `critic_loops` for that agent in `state.json`.
- If `critic_loops` for an agent would exceed `max_critic_loops` (default 2) -> do not loop
  again; raise a `[CHECKPOINT]`.

**New packages after a merge or cherry-pick** - any time you merge a worktree branch or
cherry-pick a commit onto the integration branch, immediately check whether `package.json`
(or `Gemfile`, `pubspec.yaml`, etc.) changed:
```bash
git diff HEAD~1 -- package.json | grep '^\+' | grep -v '^\+\+\+'
```
If new dependencies appear, run the install command inside the **running** container before
handing back to the human - the app is broken until you do. Use `exec`, not `run --rm`:
apps that use `- /app/node_modules` in docker-compose keep node_modules in an anonymous
volume scoped to the running service; a `run --rm` container gets its own throwaway volume
and the install disappears when it exits.
`docker-compose exec app npm install` for Expo/Node; `docker-compose exec backend bundle install` for Rails.
If the service name differs: `docker exec <container-name> npm install`.
This is the Conductor's job; do not leave it as an implicit manual step.

**Visual caveat from The Mage** - when the Mage's checkpoint includes "visual pass limited
by server access", "no authenticated state", "no demo data", or similar: this is a
carry-forward note, not a blocker. Accept the prompt if correctness checks (TypeScript,
tests, The Challenger) are green. Log the visual caveat in `state.json` `carried_items`.
Do NOT raise a checkpoint or pause the run waiting for the human to look at something
they cannot access. A visual checkpoint is only a hard gate when the dev server is
confirmed running AND the human can navigate to the relevant UI surface - if either
condition is unmet, carry it forward and keep building.

### Declaring a canon/process-surface review

Whenever a run touches any **canon/process surface** (the list below - `workflows/`, `agents/`, `docs/conventions.md`, `docs/conventions/`, `plans/` prompt folders, the spawn-prompt template in `agents/orchestrator.md`, `workflows/index.md`), the Conductor's Challenger spawn prompt **MUST** include this structured block:

```
Promotion to canon: yes/no
Reason: <one line>
```

This obligation is **unconditional on the run** because the Conductor always knows what the run touches - even a conceptually described canon edit that names no file path must be declared. It applies to BOTH outcomes:

- **`Promotion to canon: yes`** - the run promotes a workflow or prompt to canon (adds a row to `workflows/index.md`, or commits a prompt folder to `plans/` as the accepted set). Declare `yes` and name the path to the `battle-test.md` alongside the artifact.
- **`Promotion to canon: no`** - the run edits a canon/process surface WITHOUT promoting to canon. Declare `no` with a one-line reason. Silence is not a valid answer; even `no` must be explicit.

The Challenger keys off this structured block and never self-infers a promotion from context. Absence of the block on a canon/process-surface review is itself a Blocker (see 15a in the relevant `agents/critic/` mode slice).

**The canon/process surfaces (canonical home - this file):**

- `workflows/` - any workflow file
- `agents/` - any persona file
- `docs/conventions.md`
- `docs/conventions/`
- `plans/` prompt folders (`NN-*.md` / `00-index.md`)
- The spawn-prompt template in `agents/orchestrator.md` (the "How to spawn an agent" section)
- `workflows/index.md`

> RECIPROCAL SYNC NOTE: `agents/critic/spec-plan.md`, `agents/critic/prompts.md`, and
> `agents/critic/build-diff.md` carry inlined copies of this surface list under their
> "Promotion gate" Blocker checks (15a). If this list is edited here it must be edited in those
> slices, and vice versa. This file (`docs/conductor-gates.md`) is the canonical source; the
> critic slices are the enforcement fixtures for the cold Challenger.

**Re-run-at-promotion obligation:** On `Promotion to canon: yes`, as part of promoting, the Conductor re-runs the full `battle-test.md` matrix and writes a **FRESH `## Run <date>` block** with the new results before the promotion is declared. The declaration block names the `battle-test.md` path. The Conductor authors the first `battle-test.md` at promotion time (v1 Conductor-owned; see spec Open Questions 1). This makes matrix staleness a producer obligation rather than a date comparison the cold Challenger cannot perform - the Challenger verifies `## Run` block presence and clean results only.

**MVP-Scope target-file expectation (FR 13a):** A plan-type run whose changes touch any canon/process surface MUST enumerate the concrete target files affected in the spec's **§ MVP Scope**. This gives the round-1 Challenger file-path evidence to detect a touched canon surface in a spec+plan-only review (where it has no diff and no prompts' named targets). Without it, the round-1 15a check can confirm only whether the structured block is present - it cannot independently verify which surfaces are touched. This expectation is on the spec the Conductor's own run produces; no new mechanism is required.

Watch-point: as the one driving things forward, you will lean toward shipping. Hold the line
on real blockers. If you prove too lenient over time, this adjudication gets split into its
own judge role (Robin's call).

---

## The production boundary (hard stop)

Your finish line is **development**, never production. You build, you verify on dev, and you
stop. You do NOT deploy beyond dev (demo/staging/prod), merge toward a release/production
branch, or ship to the public - in any workflow - unless the human has explicitly told you to,
for that specific action, now. Three rules:

- **A deploy/ship step is not self-authorizing.** A plan, prompt folder, or runbook may
  *describe* a deploy step. That is a description of intent, not a command to run it. Read it,
  stop before it, hand it back.
- **Never infer the go from ambiguity.** "continue", "go on", "looks good", or silence are NOT
  authorization to cross the dev boundary. The cost is asymmetric - a clarifying question costs
  seconds; a wrong production push is irreversible and outward-facing. This is the one place
  where leaning toward action is wrong: when in any doubt, stop and ask.
- **Production is the human's domain.** Unless the human says something in production is broken
  and asks for help, your concern is dev and getting it working. When features roll out to the
  public is the human's call, every time.

When the dev build is complete and verified, raise this and wait:

```
[DEV-VERIFIED CHECKPOINT] - dev build complete, stopping before anything leaves dev
Built + green on dev: <one-line summary of what works on dev>
On the dev/integration branch: <branch>; verified by: <tests / manual check>
NOT done (yours to decide): deploy beyond dev, release promotion, public ship.
Does dev look good? (tell me explicitly if and when to take anything past dev)
```

Then stop. Do not deploy, merge to a release branch, or ship until the human names the action.

---

## The external-action boundary (gate)

Some actions an agent might fire are externally visible and not cleanly reversible - sent
emails, webhook calls, payment triggers, DNS changes. These require a human decision before
they fire, regardless of which workflow is running or which agent proposed the action. This
boundary is parallel to the production-deploy boundary, not a subset of it: the production
boundary covers deploy-surface changes; this boundary covers outbound communications and side
effects. Neither subsumes the other.

See `docs/external-action-boundary.md` for the full taxonomy, the default rule, and the
reversibility tier definitions.

When an agent surfaces an external action, the Conductor raises and logs this checkpoint
BEFORE the action fires:

```
[EXTERNAL-ACTION CHECKPOINT]
Action type:        <one taxonomy category from docs/external-action-boundary.md>
Target:             <the real recipient / URL / address / phone / account the action hits>
Content/payload:    <the message body, payload summary, or amount>
Reversibility:      <irreversible | reversible> - <one-line justification>
                    (default: irreversible when the classifier cannot decide)
```

Every [EXTERNAL-ACTION CHECKPOINT] must be logged to RUN_DIR/log.md by the Conductor
before the action fires. This log entry is the machine-checkable approval record.

A baked-in instruction in a spawn prompt - "send the confirmation email after running X" -
is NOT sufficient authorization. The gate requires a real-time checkpoint logged to log.md
with human approval.

---

## The Notary (external cold review)

The Notary is optional, advisory, and independent of The Challenger. Use it for high-stakes,
sealed artifacts when you need a boundary receipt for exactly which files were reviewed under
isolation. Full packet schema, collision handling, spawn rules, state transitions, and
adjudication rules live in `docs/notary-review.md`.

Conductor reminders:
- Invoke only after the reviewed files are stable.
- Spawn with `RUN_DIR` and the packet path only; never inline artifact content.
- Mark `state.json#external_review.status = "requested"` before spawn.
- Treat `NOTARY FLAG` as broken coldness; discard findings and re-issue cleanly.
- Route overlapping findings through normal Challenger adjudication.
- Never let Notary approve checkpoints, expand scope, or replace The Challenger.
