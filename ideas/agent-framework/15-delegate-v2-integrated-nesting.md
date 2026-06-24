---
priority: bundle-15
status: idea (spike-validated 2026-06-24)
suggested-workflow: feature
suggested-run-slug: delegate-v2-integrated-nesting
source-ideas:
  - done/09-principal-delegate.md (shipped v1; this is its v2)
  - done/14-delegate-merge-gate-verification.md (shipped; its verifying logic moves into the cold reviewer)
---

# 15. Delegate v2 — integrated nesting topology

## Purpose

Put the Delegate where it was always meant to be: on top. The Delegate becomes the session
Robin talks to, and it spawns the Conductor as a subagent the same way the Conductor spawns its
specialists. Robin hands the Delegate a task; the Delegate runs the Conductor and handles every
checkpoint below it; only genuine forks bubble up. This is the original Bundle 09 idea
(`done/09-principal-delegate.md:21-46`), built the integrated way instead of through a shell
file-mailbox.

The shipped v1 inverted the direction: the **Conductor** spawns the **Delegate** per checkpoint
through a file-mailbox bridge (watcher.sh + `claude -p --bare`). That inversion was not the
intent — it was a workaround for platform limits that no longer exist.

## Why v1 was a file-mailbox (and why that's now legacy)

The intended topology needs two things the Claude Code subagent layer could not do when Bundle
09 was designed:

1. A subagent (the Conductor) spawning its own subagents (the specialists) — nested spawning.
2. A subagent returning, then being resumed later with its full context — so an escalation
   doesn't cold-restart the whole run.

Without those, the only way to get a cold per-checkpoint reviewer without a live PTY relay was a
shell bridge that stages artifacts and spawns a headless reviewer. That bridge (7 scripts:
watcher.sh, await-verdict.sh, verdict-write.sh, ledger-append.sh, notify-escalation.sh,
delegate-launcher.sh) is plumbing that exists only to route around the two missing capabilities.

Both capabilities have since landed:

- **Nested subagent spawning** — supported since Claude Code v2.1.172, with a fixed depth limit
  of 5 levels below the main session. A Conductor subagent spawning Analyst / Architect /
  Challenger / build party sits at depth 2-3, well inside the limit.
- **Resumable subagents** — a returned subagent (`general-purpose` or a custom type; not Explore
  / Plan) keeps its entire transcript and resumes via `SendMessage` to its agent ID, picking up
  exactly where it stopped.

The single hard constraint: a subagent cannot call `AskUserQuestion` — it cannot pause mid-run
to ask Robin and resume in place. That does not block this topology, it shapes it (see below).

## Spike evidence (2026-06-24)

A hermetic round-trip proved all three legs before this bundle was written:

- A top-level session spawned a "Conductor" subagent (`general-purpose`).
- That Conductor subagent **spawned an "Analyst" sub-subagent** (depth 2, id `a578995fb2751c9c4`)
  and consumed its result — nested spawn confirmed.
- The Conductor hit a simulated fork ("Python or Go?"), and instead of trying to ask the human,
  **returned to its caller** with the escalation question and a state snapshot carrying a unique
  token — return-on-escalation confirmed; it handed back a resumable id (`ae4afa3477f2caea9`).
- `SendMessage` relayed "Robin's call: Go" to that id. The Conductor **resumed with context
  intact**: it echoed the unique token, restated the Analyst's REQ/EDGE lines from memory, and
  applied the decision — with `tool_uses: 0`, i.e. it answered purely from preserved transcript,
  no re-spawn.

The `tool_uses: 0` on resume is the proof that matters: the run state survived the
return/resume boundary with no rework.

## The topology

```
Robin ── task ──▶ Delegate (top-level session; owns the human conversation)
                    │  spawns (Agent tool)
                    ▼
                 Conductor (subagent; runs the workflow)
                    │  spawns specialists (Agent tool, nested)
                    ▼
                 Analyst / Architect / Challenger / Cleric / Spellwright / build party
                    │
   routine checkpoint ── Delegate spawns a fresh COLD reviewer sub-spawn ▶ verdict ▶ proceed/revise
                    │
   genuine fork ────── Conductor RETURNS to the Delegate
                    ▼
                 Delegate asks Robin (AskUserQuestion) ── Robin answers ──▶
                 Delegate resumes the Conductor via SendMessage (context intact)
```

The Conductor never talks to Robin. The Delegate owns the human conversation; the Conductor
owns the orchestration; the cold reviewer owns the verdict.

## What changes in the personas

- **Conductor (`agents/orchestrator.md`):** at a genuine escalation it **returns to its caller**
  with a structured escalation block, instead of emitting an interactive `[CHECKPOINT]` to the
  human. It loses `AskUserQuestion` as a subagent; routine checkpoints it still resolves itself
  (or via the cold reviewer). Everything else — triage, spawning the cast, adjudicating the
  Challenger, writing run-dir artifacts — is unchanged.
- **Delegate (`agents/delegate.md`):** gains a top-level **manager/relay mode** (owns the Robin
  conversation, spawns and resumes the Conductor, decides what bubbles up) on top of the existing
  **per-checkpoint critic mode**. This is the two-mode Delegate the original idea named
  (`done/09-principal-delegate.md:388`): relay loop + per-checkpoint critic, now both in-session.

## Preserving the Delegate's coldness

The shipped Delegate's whole value is that it reviews the artifact cold, never having seen the
argument that produced it (`agents/delegate.md:9-13`). A top-level manager that has been relaying
and watching the Conductor is **warm** — it has seen everything. If the manager also wrote the
verdict, the coldness guarantee dies and the gate-theater rule (`index.md`) is violated.

Resolution: the warm manager spawns a **fresh cold reviewer sub-spawn per checkpoint** for the
actual gating verdict — new context, artifact-only, exactly like today's headless Delegate, but
spawned in-session via the Agent tool instead of by a shell watcher. Manager owns the loop;
cold reviewer owns the verdict; coldness preserved.

## What survives from Bundles 09 and 14

- **Bundle 14's verifying mode survives whole.** The integration-gate checklist (re-run the
  claimed gates, scope-diff `base...branch`, reproduce every claimed-pre-existing red at the
  merge base, confirm clean fast-forward) is the highest-value content and is independent of how
  the reviewer is spawned. It moves into the cold reviewer sub-spawn. The Track-3 regression
  fixture and the standing-suite cases carry over.
- **The verdict schema, the decision ledger, and the FR-44 charter boundary survive.** Verdicts
  are still `proceed | revise | escalate`; the ledger is still append-only; the reviewer still
  models flow-and-gating, never Robin's preferences.
- **What becomes legacy:** the file-mailbox plumbing — watcher.sh, await-verdict.sh,
  verdict-write.sh, the NN-request/NN-verdict/NN-context staging protocol, and the
  `claude -p --bare` spawn invocation. In-session Agent-tool orchestration replaces it. Keep v1
  runnable as a fallback for hosts where nested spawning is unavailable until v2 is proven.

## The token tension, revisited

Bundle 09 chose file-reasoning to dodge the PTY relay's cost (~52M tokens driving a live TUI).
The integrated model keeps that win — there is no PTY, no polling, no ANSI redraw. The Conductor
runs headless as a subagent and writes its run-dir artifacts as it goes (so Robin can still watch
via `log.md` / `state.json` without a live terminal). The manager's context grows with each
resume and each Robin exchange, but that is far below the relay's cost. Bundle 14's tiering still
applies: cheap cold reviews at routine checkpoints, the expensive re-execution pass only at the
~once-per-run integration boundary.

## Acceptance boundary

A real `feature` run completes with the Delegate as the top-level session: Robin gives it one
task, it spawns the Conductor subagent, the Conductor spawns the cast and runs the workflow, the
cold reviewer gates each checkpoint, a genuine fork returns to the Delegate which asks Robin and
resumes the Conductor with context intact, and the run finishes with Robin having answered only
genuine forks — no routine checkpoint reached him. The Bundle 14 integration-gate verification
runs inside the cold reviewer and the Track-3 fixture replays green.

## Out of scope (follow-on)

- **v3 self-audit gate** (a cold auditor re-reviews a blind sample of `proceed`s) remains the
  prerequisite for running the Delegate loop **unattended** (`docs/delegate-bridge.md:319`,
  FR-43). Bundle 15 makes **attended** integrated operation clean; unattended still waits on the
  self-audit gate. Promote that as its own bundle once v2 is proven on real runs.
- The **Principal** (preference-modeling) stays explicitly deferred (CLAUDE.md three-role table).

## Relationship to other bundles

- **Is the v2 of Bundle 09 (shipped v1).** Same role, intended topology, replacing the bridge.
- **Absorbs Bundle 14 (shipped)** as the cold reviewer's integration-gate behavior.
- **Complements Bundle 05 (Notary)** — still a separate cold *artifact* attestation on demand.
- **Gate-theater rule still binds:** the cold reviewer sub-spawn is the script/Challenger-checkable
  enforcement; the warm manager never self-grades its own proceeds.
