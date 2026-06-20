---
priority: bundle-09
status: idea
suggested-workflow: feature
suggested-run-slug: principal-delegate
relates-to: bundle-05 (complement — warm process reviewer vs cold artifact reviewer); no hard framework dependency
---

# 09. Principal delegate

> Bundle 9 in the roadmap's bundle-numbering (the next bundle after 8) — not the same as
> `source-notes/09-close-out-reusable-learning-pass.md`, which is a source-idea number in a
> different namespace and already shipped inside Bundle 2. This bundle is the **complement of
> Bundle 05**: 05 is a cold *artifact* reviewer, this is a warm *process* reviewer that reads
> `log.md` on purpose. No hard framework dependency (see "What the delegate reads").

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

## Three roles, not one — Sidecar · Delegate · Principal

An outside review (ChatGPT) drew a separation worth adopting, and it corrects an over-collapse in
an earlier draft of this file (which fused "Principal" and "Delegate" into one role). The goal is
not "add a reviewer above the Conductor" — it's to take Robin out of *routine* coordination while
keeping his judgment on the decisions that are actually his. That splits into three genuinely
different questions:

| Role | Question | When |
|---|---|---|
| Sidecar (05) | Is this artifact sound, to an outsider? | cold, advisory, on demand |
| Delegate | Does Robin need to see this? | every checkpoint — this bundle, now |
| Principal | What would Robin decide? | genuine forks only — a later layer |

The **Delegate** is a flow-and-gating role: it reviews how the Conductor handled the Challenger,
continues routine work, requests revisions, and escalates. It never models what Robin *believes* —
only whether a decision is the *kind* that needs him. The **Principal** is a different thing: a
predictor of Robin's actual call on a fork, learned from the decision ledger. A decision can be one
Robin would obviously approve and *still* be one the Delegate routes to him because it's
irreversible; a fork can be novel but low-stakes. Keeping the two separate is the safety property —
the Delegate must not quietly substitute its own taste for Robin's on a real fork; it either
escalates, or (later) consults the Principal's *calibrated prediction*.

Where this diverges from the outside review's topology: the Principal and the Sidecar are
**advisors the Delegate consults**, not vertical command layers between Robin and the Conductor.
The Delegate owns the flow and pulls in a cold Sidecar review or a Principal prediction when the
decision needs it:

```
        Conductor ──checkpoint──▶ Delegate ──proceed / revise──▶ Conductor
                                     │
                      ┌──────────────┼────────────────┐
                      ▼              ▼                 ▼
                Sidecar (cold   Principal (predict   Robin
                artifact rev.)  Robin's call + conf) (final authority,
                                                     genuine forks only)
```

This bundle builds the **Delegate** (plus the bridge and ledger below). The **Principal** is a
later layer — it can't model Robin before the ledger has data to learn from — defined in "The
Principal" below so the boundary is set now and nothing fuses the two roles later.

## Why Claude, not Codex

This was previously done manually: hand the session ID to Codex at the first checkpoint,
Codex resumes with `claude -r`, finds issues, acts as critic. It worked well. But Codex
runs out of tokens quickly on a full run transcript, which caps how deep into a run it can
go before needing a handoff back.

Running the delegate in Claude raises that ceiling — bigger context budget, the same critic
instinct. But it does not by itself remove the burn: resuming the full live session is expensive
no matter who runs it (see "What the delegate reads" below). Claude buys headroom; the
file-reading architecture is what actually controls the cost.

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
forward from the last one. That makes the per-checkpoint cost *low-slope* instead of the live
session's compounding growth — with one caveat the slicing note below fixes.

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
- the **current checkpoint's slice** of `log.md` — the Challenger findings and the Conductor's
  adjudication for this checkpoint (this is the point); not the whole file (see below)
- `state.json` — phase, phases_complete, open questions
- `docs/conventions.md` and `LORE.md` — the framework's own doctrine, to catch spec-compliant
  doctrine violations (warm doctrine, not secret)
- The task brief + acceptance criteria (warm on Robin's intent, by design)
- Its own persona file (critic checklist, escalation rules)

Does **not** carry:

- The Conductor's resumed live session transcript — the token sink; read the files instead
- Any prior checkpoint's invocation context — each call is fresh
- The whole of `log.md` — only the current checkpoint's slice (see below)

### Keeping it flat (log.md grows, so slice it)

One honest correction: `log.md` itself grows with the run — every phase and every Challenger review
appends to it — so reading the *whole* file at checkpoint 50 is not flat, it's linear. The fix is
that the delegate reads only the **current checkpoint's section**, delimited by a boundary marker
the Conductor writes at each checkpoint (a `<!-- checkpoint NN -->` line in `log.md`, or
per-checkpoint files under `log/NN.md`). Continuity across checkpoints comes from the short rolling
`delegate-summary.md` (below), not from re-reading history. With slicing the per-checkpoint read is
genuinely flat; without it the "flat" claim is aspirational. The boundary marker is a small
`agents/orchestrator.md` / `execute-plan.md` change — and the only real framework dependency this
bundle now carries.

### The decision ledger (auditability)

A fresh per-checkpoint invocation has no memory of what it decided at earlier checkpoints, so on
its own it cannot author the run-end summary or let Robin verify it escalated the right things.
Fix: every checkpoint invocation **appends** a structured entry to a delegate-owned ledger,
`RUN_DIR/delegate-decisions.md` — a fixed header so it's greppable and the summary can be generated,
not hand-rolled:

```text
## Checkpoint NN — <timestamp> — <proceed | revise | escalate>
Rationale: …
Borderline: … (or none)
Refs: <sidecar review path | Principal prediction | none>
```

At run end the delegate writes a *separate* `RUN_DIR/delegate-summary.md` — decisions grouped by
type, every escalation and borderline call surfaced — so Robin spot-checks the summary, not 50 raw
entries. That rolling summary doubles as the cross-checkpoint continuity context (see "Keeping it
flat"). This is the mechanism behind the last two "Done when" bullets — without it they are
unenforceable.

Each entry also names its **borderline calls** — anything the delegate considered escalating and
decided not to, with one line of why. That turns the dangerous case (silent non-escalation) into
an auditable list rather than an invisible negative: Robin reviews the borderline items, not the
absence of them.

When the delegate pulls in a cold Sidecar review (05) for a high-stakes artifact, the ledger entry
references that review by path — so the provenance of an outside opinion is visible without
complicating the Sidecar's cold contract.

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
- The Conductor is on a path that is **spec-compliant but violates the framework's own doctrine** —
  complex machinery where the simplicity / over-engineering principle argues against it, or new
  machinery a convention already covers — even when nothing in the spec forbids it. (This is why the
  delegate reads `docs/conventions.md` + `LORE.md`.)

Everything else: handle it, append it to the decision ledger, keep moving.

## Model routing

The **Delegate** is one role with two invocation modes (relay loop + per-checkpoint critic). The
**Principal** is a separate role, not a third mode of the Delegate — the earlier draft wrongly
fused them; see "Three roles" above. Express tiers in the framework's provider-neutral vocabulary
(`standard` / `strong` / `frontier`, resolved via `config/runtimes/`), not raw model names —
hardcoding "Sonnet"/"Opus" fights routing that already exists.

| Role / mode | Tier | Reasoning |
|---|---|---|
| Delegate — relay loop (drives Conductor, talks to Robin) | standard | Flow control; escalation logic is structured matching. May self-bump to `strong` for one checkpoint on a novel interpretation, with a ledger line noting why |
| Delegate — per-checkpoint critic | standard | Critic checklist is pattern-matching; escalate one invocation to `strong` only when something hard surfaces |
| Principal — decision predictor (later) | standard | Pattern-matches a fork against ledger doctrine to predict Robin's call + confidence; escalate to `strong` for high-stakes forks |
| Conductor | unchanged | Its workflow default (`strong`); drives the run and adjudicates cross-agent conflicts |

Neither the Delegate nor the Principal needs raw reasoning power; good prompting (a clear checklist,
a well-curated ledger) beats model tier here. Keep the heavier tier where the real judgment load
sits — the Conductor and the specialists it spawns.

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
2. Add `delegate` to the CLAUDE.md agent table and the routing tier table, plus the three-role
   contrast table (Sidecar / Delegate / Principal — cold/warm axis, authority, when invoked) in
   CLAUDE.md or LORE.md so it's impossible to later add "Principal" as a sub-bullet under Delegate.

v2 — the bridge is where the value lives, not automation layered on top. Its full design — the
file mailbox, the blocking wait, the watcher, the verdict schema, and the escalation channel — is
in "The bridge" below.

Be honest about the split: v1 is a persona spec, v2 is the delegate. Until the bridge exists,
"loop on checkpoints" still needs a human actor — which is Robin, the person this is meant to
free.

## The bridge (how the Conductor gets unblocked)

The open question the rest of this doc leaves is: with the delegate reasoning in a *separate*
cheap context, how does the live Conductor receive the verdict and proceed — without anyone paying
to resume the full transcript? Answer: a file mailbox in the run dir, and the model only ever
wakes on an actual event. The heartbeat instinct is right, but the heartbeat belongs in the
**shell/watcher, not in billed model turns** — a model that wakes to poll re-sends its transcript
every tick; a shell loop (or a blocking wait) costs nothing.

Three parties, coordinating through `RUN_DIR/checkpoints/`:

1. **Conductor** (one long-lived session, stays alive). At a checkpoint it writes
   `RUN_DIR/checkpoints/NN-request.md` (artifact path + question), then issues a **single blocking
   wait** for `NN-verdict.md` — a background process that exits when the file appears, and the
   harness re-invokes the Conductor on exit (the `Monitor`/background-Bash pattern). It generates
   zero tokens while waiting.
2. **Delegate** — a **headless one-shot** (`claude -p`) spawned per checkpoint. Reads the request +
   `state.json` + the current checkpoint's `log.md` slice + the artifact (small, flat context),
   applies the checklist, writes `NN-verdict.md`, appends to `delegate-decisions.md`, exits. No
   transcript, no growth.
3. **Watcher** — a dumb shell loop (or `fswatch`/inotify), *not* a model. Watches `checkpoints/`
   for new `*-request.md` and spawns the delegate headless. This is the heartbeat, and it's free
   because it's bash.

### Verdict schema (what the Conductor parses)

`NN-verdict.md` is a small, fixed structure so Conductor consumption is deterministic:

```markdown
## Delegate verdict — checkpoint NN
Decision: proceed | revise | escalate
Rationale: <1–2 sentences>
Required changes: <bullets, or "none">    # present iff Decision: revise
Escalation: <one-line reason, or "none">  # present iff Decision: escalate
Ledger: delegate-decisions.md#NN
```

- `proceed` — Conductor continues.
- `revise` — Conductor runs one revision loop against "Required changes" (the relay contract's
  revision loop), then the delegate re-reviews.
- `escalate` — the run pauses; the watcher surfaces the reason to Robin (below).

`agents/orchestrator.md` gets a short "consuming a delegate verdict" block: parse the structured
fields, act by Decision, and **never proceed on a malformed verdict — treat it as `escalate`.**

### Cost accounting (why this kills the sink)

- **Conductor**: pays for its own turns — unavoidable, it's the worker; pays **nothing** while
  waiting; carries **zero** delegate context.
- **Delegate**: pays per checkpoint for a *small* file-only context — flat *if it reads only the
  current checkpoint's `log.md` slice* (see "Keeping it flat"); linear if it reads the whole log.
- **Watcher**: ~free.

Two residual tradeoffs to design against, not ignore:

- **Stay alive, don't exit-and-resume.** Resuming the Conductor per checkpoint (`claude -r`) is a
  cold cache-miss on the full transcript — the exact thing that burned the hand-run version. Keep
  it alive and blocking so the prompt cache stays warm.
- **…but the cache TTL caps that.** The prompt cache is a ~5-minute window (1-hour extended). A
  checkpoint slower than that lets the Conductor's cache expire, so its next turn pays full freight
  anyway. Fast delegate turnaround, or extended cache. The big win (delegate not carrying the
  transcript) holds regardless.
- **Blocking-call ceiling**: a foreground wait maxes ~10 min; past that use background + notify.

### Failure modes the bridge must handle

The mailbox is simple, which is the point — but a few failure modes have to be handled explicitly,
not assumed away:

- **Delegate crashes / no verdict written.** The Conductor's blocking wait must time out rather than
  hang forever, and treat a *missing* verdict the same as a malformed one: escalate to Robin.
- **Duplicate or partial verdicts.** Write atomically (`NN-verdict.md.tmp` then rename) so the
  Conductor never reads a half-written file; ignore a second verdict for a checkpoint already
  resolved.
- **Watcher dies.** It's a dumb restartable process: on restart it re-scans `checkpoints/` for any
  `*-request.md` with no matching `*-verdict.md` and resumes. A request with no verdict and no live
  watcher is a stuck run — surface it, don't let the Conductor block silently.
- **Stale request.** Each request carries the checkpoint id + run-dir path; the watcher ignores
  requests for a run that has since closed.
- **Conductor dies mid-wait.** The waiting party can die too. The watcher also monitors Conductor
  liveness — a heartbeat field in `state.json` (last-progress timestamp), not just new request
  files — and a wait past a **per-checkpoint-type timeout** (high-stakes checkpoints get longer)
  escalates to Robin rather than hanging.

None of this is exotic — it's standard "file as a queue" hygiene (atomic write, idempotent consume,
restartable consumer). Worth a tiny `bridge` helper so the Conductor side stays clean.

### Escalation channel

When the delegate writes `Decision: escalate`, the watcher pings Robin and the run holds on that
one checkpoint while everything else flows. v1 default: pause + a local desktop notification.
Recommended v2: route through the existing rheo Telegram bot / M.O.T. rail so Robin can answer from
his phone and the run resumes — the concrete "only novel decisions bubble up" mechanism.

### Slices

- **v1 (proves the token claim; Robin still pulls the trigger):** Conductor writes the request and
  blocks; the delegate is a headless `claude -p` Robin runs via a one-line script when a request
  appears. Proves the mailbox, the cheap file-based review, and resume-from-verdict with no
  transcript resume. Robin no longer *reasons* at checkpoints — he runs a command.
- **v2 (autonomous):** add the watcher (file-watch → auto-spawn) + the Telegram escalation rail.
  Robin is out except for escalations.

## The Principal (later layer — predict Robin, don't replace him)

The Principal answers "what would Robin decide?" on a genuine fork — distinct from the Delegate's
"does Robin need to see this?" It is **not** built in v1, on purpose: you can't model Robin's taste
before there's data to learn from, and the Delegate's decision ledger is that data. So the Principal
is sequenced after the Delegate has run enough to accumulate ledger entries — Robin's real calls on
the forks that got escalated.

Three guards keep it from over-reaching:

- **Predictive, not authoritative, first.** The Principal emits a prediction the Delegate may use;
  Robin stays the final authority. Output is structured:

  ```text
  Predicted decision: approve | reject | revise
  Confidence: NN%
  Reasoning: <which doctrine/precedent it matches, what it checked>
  ```

- **Calibrated against the ledger before it acts, and the bar is two-dimensional.** Every escalation
  records Robin's actual decision, so the Principal's predictions can be scored against ground
  truth. Auto-acting requires BOTH high measured calibration on that *kind* of fork AND stakes below
  an explicit ceiling — a 95%-calibrated prediction still escalates if the fork is irreversible or
  touches a sensitive system. Until both hold, the prediction is advisory and the fork goes to
  Robin. Even once it auto-acts, every auto-acted call is logged as a **borderline** ledger item for
  Robin's periodic review, until trust is high enough to stop.

- **Scoped to run-fork decisions.** The Principal models Robin's calls on framework-run tradeoffs
  (scope cuts, build-vs-buy, over- vs under-engineering, which approach wins a bake-off) — the
  things that actually recur in the ledger. It is not a general "Robin values" model; that would be
  unmeasurable machinery the framework's own over-engineering test would flag.

The doctrine the Principal learns lives where the framework already keeps durable judgment — the
decision ledger plus the Bundle 02 learning loop / memory — not a bespoke store. The Principal is a
*consumer* of that accumulated judgment, which is another reason it comes after, not with, the
Delegate.

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
- The Delegate ships as a flow/gating role only; the Principal (decision prediction) is explicitly
  deferred to a later, ledger-trained layer and not fused into the Delegate
