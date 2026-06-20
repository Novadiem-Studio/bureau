---
priority: bundle-09
status: idea
suggested-workflow: feature
suggested-run-slug: principal-delegate
depends-on: a Challenger-findings split (see "Artifact allowlist"); sibling of bundle-05
---

# 09. Principal delegate

> Bundle 9 in the roadmap's bundle-numbering (the next bundle after 8) — not the same as
> `source-notes/09-close-out-reusable-learning-pass.md`, which is a source-idea number in a
> different namespace and already shipped inside Bundle 2. This bundle is a **sibling of
> Bundle 05** (both are cold reviewers gated by an artifact allowlist) and depends on the same
> Challenger-findings split 05 needs.

## The idea

Add a **delegate** role that sits above the Conductor. The user talks to the delegate;
the delegate runs the Conductor and handles everything below.

Current flow:
```
Robin → Conductor → [checkpoints] → Robin → Conductor → ...
```

With the delegate:
```
Robin → Delegate → Conductor → [checkpoints] → Delegate → Conductor → ...
                                                    ↑
                                             only novel decisions
                                             bubble up to Robin
```

The delegate:
- Takes the task from Robin
- Starts or resumes the Conductor (a new Claude Code session, or via `claude -r <sessionID>`)
- Handles every Conductor checkpoint: reads the artifact, reviews it, responds
- Acts as critic at each handoff — pattern-matching for inconsistencies, drift, thin reasoning
- Only pauses and talks to Robin when it hits something that genuinely needs a human call
- Keeps Robin informed with a short status update at key milestones, not at every step

Robin's interaction drops to: give the delegate the task, get a "done / here's what happened"
or "blocked on X — your call." Everything in between is noise Robin doesn't need.

## Why Claude, not Codex

This was previously done manually: hand the session ID to Codex at the first checkpoint,
Codex resumes with `claude -r`, finds issues, acts as critic. It worked well. But Codex
runs out of tokens quickly on a full run transcript, which caps how deep into a run it can
go before needing a handoff back.

Running the delegate in Claude removes that ceiling. The same critic instinct, no token wall.

The protocol that worked is already written down — `CODEX.md`'s "Claude CLI relay handoff"
section — so this bundle is a port of a proven pattern into a Claude persona, not a new design.

## Relationship to the sidecar (05)

The sidecar (05) was designed around *coldness*: strict allowlist, no session context, purely
advisory. The delegate is its **complement, not its competitor** — same idea of a bounded
reviewer, opposite end of the coldness axis. The sidecar is a cold *artifact* reviewer; the
delegate is a warm *process* reviewer that reads `log.md` precisely so it can judge how the
Conductor handled the Challenger, and it carries decision authority where the sidecar is only
advisory. A delegate-run workflow could still invoke a sidecar for a formal cold review of a spec
artifact. The delegate is the higher-priority gap because it removes Robin from the loop rather
than adding another reviewer.

## What the delegate reads (token discipline, not coldness)

**Field finding (Robin, by hand):** a delegate that resumed the run with `claude -r` and had full
`log.md` context did a fine critic job. The binding constraint was never coldness — it was that
it **burned tokens very fast**. Design around that, not around an allowlist.

Diagnosis: the burn comes from resuming the Conductor's **live session** (`claude -r`), whose
transcript grows with the run and is re-sent on every turn. The fix is not to deny the delegate
context — it's to stop it from carrying the whole transcript. The delegate reasons in its **own
short-lived context** that reads the compact, durable run-dir handoff — `state.json`, `log.md`,
and the artifact under review — the same surface the framework already uses to resume a run from
disk. It never resumes the full live session, and a per-checkpoint invocation carries nothing
forward from the last one. Context cost stays flat regardless of run length; quality doesn't drop,
because the files hold what matters.

So `log.md` is **read, not denied** — and the delegate needs it. Its lead job is reviewing the
Conductor's *adjudication* of the Challenger ("was this blocker actually closed, or waved
through?"), which is impossible without seeing the Challenger's findings and the Conductor's
response — both of which live in `log.md`. A *cold* delegate couldn't do its main job. That is the
clean division of labour with 05: the sidecar is the genuinely-cold artifact reviewer; the
delegate is the **warm process reviewer**. This removes the earlier draft's hard dependency on
splitting Challenger findings out of `log.md` — that split is at most optional tidiness, not a
blocker.

Reads per checkpoint:

- The artifact under review (`spec.md`, `plan.md`, `prompts.md`)
- `log.md` — including the Challenger findings and the Conductor's adjudication (this is the point)
- `state.json` — phase, phases_complete, open questions
- The task brief + acceptance criteria (warm on Robin's intent, by design)
- Its own persona file (critic checklist, escalation rules)

Does **not** carry:

- The Conductor's resumed live session transcript — the token sink; read the files instead
- Any prior checkpoint's invocation context — each call is fresh

### The decision ledger (auditability)

A fresh per-checkpoint invocation has no memory of what it decided at earlier checkpoints, so on
its own it cannot author the run-end summary or let Robin verify it escalated the right things.
Fix: every checkpoint invocation **appends** its call + reasoning to a delegate-owned ledger,
`RUN_DIR/delegate-decisions.md`. The run-end summary is a read over that ledger, and the ledger is
what Robin spot-checks to confirm no silent pass-through. This is the mechanism behind the last two
"Done when" bullets — without it they are unenforceable.

## Critic checklist

The delegate's review at each checkpoint is trainable. **Lead with the one check nothing else in
the pipeline runs:**

- **Adjudication review (the non-redundant job).** Does the Challenger's objection list have any
  "resolved" items the Conductor waved through without an actual fix in the artifact text? The
  Challenger reports and the Conductor decides what to act on; *no one currently reviews that
  decision.* The roadmap's own gate-theater principle names the Conductor as "the party with the
  standing bias to ship" — this is the check that closes that gap, and it is why the delegate is
  not just a second Challenger.

The remaining checks overlap the Challenger deliberately — they are a second pass over the
*Conductor's handling*, applied warm-on-intent rather than cold-on-artifact:

- Does the spec/plan reference something that was only said in conversation (not written)?
- Do the acceptance criteria map 1:1 to the plan phases?
- Are there phases with no test coverage specified?
- Does the model routing match the task weight (a heavy tier on a trivial fix, a light tier on architecture)?
- Is the scope creeping beyond what Robin asked for?

This list grows over time as patterns emerge.

## Escalation signals (when to pause and ask Robin)

These are not new — they are the escalation list already proven in `CODEX.md`'s "Claude CLI
relay handoff" section, which is exactly this protocol run by Codex by hand. **Lift that block
as the delegate's authority + escalation contract rather than re-deriving a thinner version**,
and make one file canonical: once `agents/delegate.md` exists, both it and `CODEX.md` describe
the same approval authority, so per the project's canonical-copy rule one must point at the
other. The signals:

- A Challenger BLOCKER whose Architect fix looks wrong or thin
- A scope decision that would materially change the cost or timeline
- A design choice where two equally-valid approaches exist and the tradeoff is Robin's to make
- Anything touching a system Robin explicitly marked as sensitive (prod DB, billing, auth)
- Production/release deployment, public shipping, or any externally visible action — never the
  delegate's call (from the relay contract)

Everything else: handle it, append it to the decision ledger, keep moving.

## Model routing

There is **one** new role, the delegate, in **two invocation modes** — the earlier draft's
"Principal" and "Delegate" rows were the same role split by mode, not two roles. Express tiers in
the framework's provider-neutral vocabulary (`standard` / `strong` / `frontier`, resolved via
`config/runtimes/`), not raw model names — hardcoding "Sonnet"/"Opus" fights routing that already
exists.

| Mode | Tier | Reasoning |
|---|---|---|
| Delegate — relay loop (drives Conductor, talks to Robin) | standard | Rule-lookup against pre-loaded decisions; escalation logic is structured matching |
| Delegate — per-checkpoint critic | standard | Critic checklist is pattern-matching; escalate one invocation to `strong` only when something hard surfaces |
| Conductor | unchanged | Its workflow default (`strong`); drives the run and adjudicates cross-agent conflicts |

The delegate layer doesn't need raw reasoning power; good prompting (clear checklist, explicit
allowlist) beats model tier here. Keep the heavier tier where the real judgment load sits — the
Conductor and the specialists it spawns.

## Implementation sketch

**Who holds the loop is the make-or-break question, and it has to be answered first.** CLAUDE.md
is emphatic: a session running from `agent-framework/` *is* the Orchestrator (the Conductor). So
a single session cannot be both the Conductor and a delegate sitting above it. Two real options:

1. **Two sessions** — a delegate session drives a Conductor session via `claude -r <sessionID>`.
   This is the exact topology the Codex relay already uses, and the one that actually removes
   Robin from the loop. Pick this.
2. **One session, delegate entry-point** — then the delegate isn't "above" the Conductor; it's a
   different launch identity, and the CLAUDE.md "you are the Orchestrator" rule has to be amended
   to branch on it.

The token lesson from the hand-run version is the load-bearing implementation detail: **do not
let the delegate think inside a resumed `claude -r` Conductor session.** That is what burned
tokens — every turn re-sent the whole growing transcript. The delegate reads the run-dir files in
its own fresh context, decides, and hands the Conductor only a short verdict to act on. The
expensive context stays with the party that already needs it (the Conductor), paid once when it
acts on the verdict — not multiplied across the delegate's reasoning turns.

v1 — persona + protocol (note: this alone does **not** remove Robin):
1. `agents/delegate.md` — persona file, critic checklist, escalation rules, handoff protocol
   (lift the authority contract from `CODEX.md` relay mode; make one file canonical).
2. Add `delegate` to the CLAUDE.md agent table and the routing tier table.

v2 — the bridge is where the value lives, not automation layered on top:
- A checkpoint marker in the run dir triggers a fresh delegate invocation that reads
  `state.json` + `log.md` + the artifact, decides, appends to `RUN_DIR/delegate-decisions.md`,
  and writes a short verdict.
- The Conductor session consumes the verdict and proceeds — the only place the run's full context
  is carried.

Be honest about the split: v1 is a persona spec, v2 is the delegate. Until the bridge exists,
"loop on checkpoints" still needs a human actor — which is Robin, the person this is meant to
free.

## Done when

- Robin can hand a task to the delegate and not touch it again unless an escalation fires
- The delegate reasons in its own context off the run-dir files and never resumes the Conductor's
  live session — per-checkpoint token cost stays flat as the run grows
- Every checkpoint call is appended to `RUN_DIR/delegate-decisions.md`, and the delegate produces
  a run-end summary by reading that ledger: what was built, what the Challenger flagged, what
  decisions it made on Robin's behalf, and why
- The critic checklist is documented and the delegate applies it at each checkpoint, leading with
  the adjudication review
- Escalation signals are explicit enough — and the decision ledger complete enough — that Robin
  can verify the delegate escalated the right things and didn't silently pass something it should
  have flagged
