---
priority: bundle-09
status: idea
suggested-workflow: feature
suggested-run-slug: principal-delegate
relates-to: bundle-05 (complement — warm process reviewer vs cold artifact reviewer)
real-dependency: a mandatory delegate gate in every workflow + log.md slicing (see "Reality check") — NOT the cheap change an earlier draft claimed
---

# 09. Principal delegate

> Bundle 9 in the roadmap's bundle-numbering (the next bundle after 8) — not the same as
> `source-notes/09-close-out-reusable-learning-pass.md`, which is a source-idea number in a
> different namespace and already shipped inside Bundle 2. This bundle is the **complement of
> Bundle 05**: 05 is a cold *artifact* reviewer, this is a warm *process* reviewer that reads
> `log.md` on purpose. Real framework dependency: a mandatory delegate gate after every Challenger
> pass, plus `log.md` slicing — see "Reality check" (not the cheap change an earlier draft claimed).

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

## Reality check — corrections from the repo-grounded review (Codex)

A sixth review (Codex, with the working tree **and** the actual hand-run relay telemetry) found
errors the five chat reviews couldn't — they only saw this doc; Codex checked it against the code and
against what happened. **Where this section conflicts with anything below, this section wins**; the
body is kept for its reasoning, but these are the corrections.

- **The token diagnosis below is over-simplified.** Relay telemetry: ~52M input tokens, **50.2M
  cached**, 4 compactions, 5-hour window maxed. The sink was *driving a live TUI by polling* — 126
  terminal interactions, ANSI redraw noise, repeated whole-context turns, re-verification,
  interrupting stale execution — **not** the `log.md` read, and not cleanly "re-sending the growing
  transcript." Caching covered ~96%. The headless file-mailbox design still wins, but because it
  removes the PTY-driving overhead and the re-verify loop — not because it dodges a transcript.
  Treat "resume = cold cache miss / stay-alive = warm" as **unverified** (cache reuse needs prefix
  match + TTL, not process continuity).
- **There is no cheap dependency — the main review event isn't a checkpoint.** Today Challenger
  findings are followed by *immediate* Conductor adjudication and progression
  (`workflows/feature.md:33`, `bug-fix.md:81`, `execute-plan.md:106`); the run pauses only when the
  Conductor independently chooses `[CHECKPOINT]`. So the delegate cannot review "every adjudication"
  without adding a **mandatory delegate gate after every Challenger pass / build-diff review in every
  workflow** — a cross-workflow protocol change, not "one small dependency." (`log.md` slicing is
  needed *on top*, and is itself non-trivial.)
- **The delegate is gate-theater as designed — the deepest unsolved problem.** The same model writes
  the verdict, the borderline flag, the ledger, and the summary; schema validation checks *syntax*,
  not whether `proceed` was *correct*. A confidently-wrong `proceed` never self-flags borderline and
  vanishes from Robin's review — exactly what the gate-theater principle (`index.md:54`) forbids
  (Challenger-checkable or script-enforced, never self-assessed). Must be closed before v2 trusts the
  delegate. **Defined concretely as a v2 gate in "Self-audit" below** — a cold auditor re-reviews a
  random blind sample of `proceed`s; a mismatch recalibrates and surfaces to Robin. Self-reported
  confidence does **not** fix this, which is why the confidence field is dropped for an explicit
  `Uncertainties` list.
- **Least privilege: the delegate model must not write files.** A headless `claude -p` with default
  tools can edit repo/log/state — against `orchestrator.md:150`. The model **emits validated
  structured output; the shell bridge does the atomic writes**. That also gives atomic requests,
  worker-claim locking, and idempotency for free (the shell owns them), closing several bridge gaps.
- **"Two sessions" does not fix identity.** A `claude -p` launched from this dir still loads "you are
  the Conductor" (`CLAUDE.md:34`). The delegate needs a **custom system prompt + a launch context
  that doesn't auto-discover that instruction** — session count alone changes nothing.
- **Persona promotion ≠ battle-test.** `agents/delegate.md` needs the structured `Promotion to canon:`
  declaration + cold Challenger review (`orchestrator.md:543`), but the 15b battle-test rule applies
  only to promoted *workflows / prompt folders* (`conventions.md:335`); a new persona is normally
  `Promotion to canon: no`. (An earlier note here saying "needs a battle-test" was wrong.)
- **Canonical authority is misplaced.** `CODEX.md` governs only Codex sessions (`CODEX.md:3`), so the
  shared escalation contract belongs in a **neutral authority doc** both `CODEX.md` and
  `agents/delegate.md` reference — not in either.
- **No supervisor exists.** Nothing starts the Conductor/watcher/delegate, records session ID/PID,
  restarts `Monitor` after a resume (Monitor is real but **not** restored on resume), or shuts down
  at close. The bridge needs a launcher/supervisor + a Monitor restart contract.
- **Smaller, each verified:** tiers are `cheap · standard · strong · frontier · escalated`
  (`config/runtimes/README.md`), and routing needs a `config/model-policy.v2.json` entry (table fixed
  below); checkpoint id must be `{checkpoint, attempt}` + artifact hash (a verdict must not inherit
  to an edited file); `revise → re-review` needs a revision cap → escalate; "one checkpoint holds
  while everything else flows" is false (workflows are sequential — `execute-plan.md:141`); drop the
  `state.json` heartbeat (stale when blocked-by-design + a second concurrent writer) and the rolling
  summary (a third growing surface); even *designing* the Principal now (fork taxonomy, calibration)
  is speculative — keep only the cheap part (record Robin's resolved call).

Bottom line: the **idea survives**, but it's a bigger build than the body implies — a cross-workflow
gate, a privileged shell bridge with a supervisor, and an unsolved self-audit problem — and the
headline token claim needs re-grounding. v1 should still be the cheapest thing that tests the two
real questions: does a file-mailbox loop actually beat the PTY relay on tokens, and can a delegate's
`proceed` be trusted without a cold auditor.

## Empirical check — the Bundle 04 run

`output/runs/20260620-run-accounting-and-resume-signals/` is a real run where Codex operated as the
delegate from the first checkpoint, at a cost of ~2 full Claude sessions. What it shows:

- **The role earned its keep.** After the cold Challenger passed the prompts (round 2 → `[1 blocker]`,
  focused verify → `[0 blockers]`), Codex-as-delegate caught **20 build-breaking defects across three
  HOLD rounds** (5 → 11 → 4): `command not found` from function order, `set -u` aborts on an absent
  log, `--arg`/`--argjson` boolean bugs, atomic-write-across-filesystems, schema-key drift. The
  strong Challenger *and* the Conductor's adjudication had passed every one — exactly the
  adjudication-review catch the delegate exists for.
- **Routing confirmed.** That reviewer was opus-class; a `standard`/Sonnet delegate would plausibly
  have said `proceed` on those build-breakers → critic tier = `strong`.
- **The efficiency win is the mechanism, not the slicing.** Codex's cost was PTY polling, ANSI
  redraw, 4 compactions, ~52M accumulated input tokens. A headless one-shot removes all of that:
  fresh `claude -p` per round, read → verdict → exit. Order-of-magnitude ~4 rounds × ~70–90k ≈
  0.3–0.4M vs. ~52M input (~6–7M even at cache pricing) — ~10× cheaper, and more reliable (no lossy
  mid-review compaction).
- **But "cheap per checkpoint via slicing" is oversold for this kind of review.** The work that
  dominated was full-artifact defect hunting — a bug in `prompts.md` (94 kB) against the `spec.md`
  contract (109 kB) — which is **not** sliceable; each such review reads ~50 kB regardless. And the
  round count (~4) is intrinsic (fixing 5 defects revealed 11 more); the design cuts neither. The win
  is structural (no cross-round accumulation / PTY / compaction), not per-round flatness.
- **It would not have removed the human.** Catching those 20 needed a capable reviewer's judgment —
  which is also the gate-theater answer in the favourable direction: a strong delegate caught what a
  strong Challenger missed.

## Lean review pattern (Bundle 04 retro)

Codex's verdict after running as the delegate on that bundle: "fun, but magnificently token-hungry."
Its recommendations are the operating model for any external/delegate review — Codex's estimate is a
70–90% token cut with most of the value kept. They reshape *when* and *how* the delegate reviews, not
whether it should exist:

- **Gate the external review; don't run it every checkpoint.** Engage the delegate / Notary at a few
  high-value gates — design, final spec/plan, final prompts — not every internal loop. The internal
  loops stay the Challenger's job.
- **One critic per pass.** The Challenger handles the normal revision loops; the external reviewer is
  the *single* independent adversarial pass at the gate, never a parallel reviewer on every round.
- **Review diffs, not whole artifacts.** The request packet is a compact `review-checkpoint.md` —
  changed decisions, the diff, the risks, the approval asked for — not the full 94 KB artifact and
  not the live terminal stream. This is the cost lever I underweighted in "Empirical check": a
  *whole-artifact* read is expensive, but a *diff* packet is dramatically cheaper, and most review
  only needs the diff.
- **Cap the external review at one audit + one verification, then escalate.** Don't burn another
  broad pass on a still-disputed point — escalate it. (Same shape as the delegate's revision cap.)

The lean end-to-end shape:

```text
Claude workflow → Challenger clean → compact diff packet → one Notary audit
  → Claude fixes → targeted Notary re-verify → done
```

This is what tips the v1 token question favourable: the hand-run relay was expensive partly because
it reviewed everything, every checkpoint, as a live stream. Gated, diffed, once-per-pass review is
where the 10x (or more) actually comes from.

## Three roles, not one — Notary · Delegate · Principal

An outside review (ChatGPT) drew a separation worth adopting, and it corrects an over-collapse in
an earlier draft of this file (which fused "Principal" and "Delegate" into one role). The goal is
not "add a reviewer above the Conductor" — it's to take Robin out of *routine* coordination while
keeping his judgment on the decisions that are actually his. That splits into three genuinely
different questions:

| Role | Question | When |
|---|---|---|
| The Notary (05) | Is this artifact sound, to an outsider? | cold, advisory, on demand |
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

Where this diverges from the outside review's topology: the Principal and The Notary are
**advisors the Delegate consults**, not vertical command layers between Robin and the Conductor.
The Delegate owns the flow and pulls in a cold Notary review or a Principal prediction when the
decision needs it:

```
        Conductor ──checkpoint──▶ Delegate ──proceed / revise──▶ Conductor
                                     │
                      ┌──────────────┼────────────────┐
                      ▼              ▼                 ▼
                Notary (cold    Principal (predict   Robin
                artifact rev.) Robin's call + conf) (final authority,
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

## Relationship to The Notary (05)

The Notary (05) was designed around *coldness*: strict allowlist, no session context, purely
advisory. The delegate is its **complement, not its competitor** — same idea of a bounded
reviewer, opposite end of the coldness axis. The Notary is a cold *artifact* reviewer; the
delegate is a warm *process* reviewer that reads `log.md` precisely so it can judge how the
Conductor handled the Challenger, and it carries decision authority where The Notary is only
advisory. A delegate-run workflow could still invoke The Notary for a formal cold review of a spec
artifact. The delegate is the higher-priority gap because it removes Robin from the loop rather
than adding another reviewer.

## What the delegate reads (token discipline, not coldness)

**Field finding (Robin, by hand):** a delegate that resumed the run with `claude -r` and had full
`log.md` context did a fine critic job. The binding constraint was never coldness — it was that
it **burned tokens very fast**. Design around that, not around an allowlist.

Diagnosis (**superseded — see "Reality check"**: relay telemetry shows the real sink was driving a
live TUI by polling, with caching covering ~96% of input tokens, not the transcript resume): the
original theory was that the burn comes from resuming the Conductor's **live session** (`claude -r`),
whose transcript grows with the run and is re-sent on every turn. The fix is not to deny the delegate
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
clean division of labour with 05: The Notary is the genuinely-cold artifact reviewer; the
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
genuinely flat; without it the "flat" claim is aspirational. The boundary marker is **not** the only
dependency (an earlier draft said so — see "Reality check"): the bigger one is that the adjudication
isn't a checkpoint today, so a delegate gate must be added to every workflow. And the marker is less
trivial than it looks — runs scatter review / adjudication / reversals across unrelated `##` headings,
so slicing needs unique `{checkpoint, attempt}` IDs and explicit end boundaries.

### The decision ledger (auditability)

A fresh per-checkpoint invocation has no memory of what it decided at earlier checkpoints, so on
its own it cannot author the run-end summary or let Robin verify it escalated the right things.
Fix: every checkpoint invocation **appends** a structured entry to a delegate-owned ledger,
`RUN_DIR/delegate-decisions.md` — a fixed header so it's greppable and the summary can be generated,
not hand-rolled:

```text
## Checkpoint <id> attempt <n> — <timestamp> — <proceed | revise | escalate>
Uncertainties: … (or none)        # any entry ⇒ borderline (replaces self-reported confidence)
Rationale: …
Borderline: … (or none)
Refs: <notary review path | none>
Robin's call: …   # filled in when an escalation resolves — the cheap training label to keep now
```

The shell bridge writes this entry, not the model (least privilege — see "Reality check").

At run end the delegate writes **one bounded** `RUN_DIR/delegate-summary.md` — decisions grouped by
type, every escalation and borderline call surfaced — so Robin spot-checks the summary, not 50 raw
entries. (Keep only the append-only ledger + this close-out summary; an earlier draft added a
*rolling* summary as continuity context, but it grows too and undermines the flat-cost goal — drop
it, per "Reality check.") This is the mechanism behind the last two "Done when" bullets — without it
they are unenforceable.

Recording `Robin's call:` on every escalation **from day one** is the cheap, do-it-now half of "the
Principal learns from the ledger" — so you don't reach that phase and find the data was never kept.
Do **not** pre-design a fork taxonomy or calibration system now; that is the speculative half (see
"Reality check").

Each entry also names its **borderline calls** — anything the delegate considered escalating and
decided not to, with one line of why. That turns the dangerous case (silent non-escalation) into
an auditable list rather than an invisible negative: Robin reviews the borderline items, not the
absence of them.

When the delegate pulls in a cold Notary review (05) for a high-stakes artifact, the ledger entry
references that review by path — so the provenance of an outside opinion is visible without
complicating The Notary's cold contract.

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

These come from the relay contract proven by hand in `CODEX.md`'s "Claude CLI relay handoff"
section. **Lift that block verbatim rather than re-deriving a thinner version** — an earlier draft of
this list silently dropped ~8 of its items (restored below; Codex caught it). Because `CODEX.md`
governs only Codex sessions (`CODEX.md:3`), the canonical contract lives in a **neutral authority
doc** that both `CODEX.md` and `agents/delegate.md` reference — not in either. The signals:

- A Challenger BLOCKER whose Architect fix looks wrong or thin
- A scope decision that would materially change the cost or timeline
- A design choice where two equally-valid approaches exist and the tradeoff is Robin's to make
- Anything touching a system Robin explicitly marked as sensitive (prod DB, billing, auth)
- Production/release deployment, public shipping, or any externally visible action — never the
  delegate's call (from the relay contract)
- A destructive or hard-to-reverse action, a secrets/access change, billing, or unusual
  security/privacy risk
- An unresolved Blocker, an **exhausted revision limit**, or a specialist conflict that can't be
  adjudicated from written evidence
- Unexpected scope expansion, or a change overlapping Robin's unrelated work
- The Conductor is on a path that is **spec-compliant but violates the framework's own doctrine** —
  complex machinery where the simplicity / over-engineering principle argues against it, or new
  machinery a convention already covers — even when nothing in the spec forbids it. (This is why the
  delegate reads `docs/conventions.md` + `LORE.md`.)

(Authority boundary, not a per-checkpoint signal:) relay authority ends when the run closes, Robin
takes the session back, or Robin revokes it.

Everything else: handle it, record it in the decision ledger, keep moving.

## Model routing

The **Delegate** is one role with two invocation modes (relay loop + per-checkpoint critic); the
**Principal** is a separate, later role (see "Three roles"). Tiers use the framework's real
vocabulary — `cheap · standard · strong · frontier · escalated` (`config/runtimes/README.md`; under
Claude `standard→sonnet`, `strong/frontier→opus`), not raw model names. Routing the delegate needs a
role entry in `config/model-policy.v2.json`, and the watcher must pass the **resolved** model to
`claude -p` — a CLAUDE.md table row alone does nothing.

| Role / mode | Tier | Reasoning |
|---|---|---|
| Delegate — relay loop | standard | Flow control; structured-matching escalation logic |
| Delegate — per-checkpoint critic | **strong** (start here) | It must overrule a `strong` Conductor + Challenger on adjudication; there is **no evidence** `standard`/Sonnet can do that reliably (the proven relay used a high-capability reviewer). Drop to `standard` only if measured to hold |
| Principal — decision predictor (later) | tbd | Out of v1 scope |
| Conductor | unchanged | Workflow default (`strong`) |

The earlier "good prompting beats model tier, keep the delegate on `standard`" claim is **unverified**
for the adversarial-overrule task — treat the critic tier as `strong` until a cheaper tier is shown
to match it.

**How to measure it (don't guess).** The Bundle 04 run is a ready-made benchmark: a known set with
20 real build-breakers a `strong` Challenger + Conductor passed (see "Empirical check"). Replay its
prompts-stage review with a `standard` and a `strong` delegate, blind, and compare defect-catch rate
and cost. Drop the critic tier to `standard` only if it catches the same class at materially lower
cost; otherwise it stays `strong`. This turns the tier choice into a measurement, not an opinion.

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
   contrast table (Notary / Delegate / Principal — cold/warm axis, authority, when invoked) in
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
## Delegate verdict — checkpoint <id> attempt <n>
Decision: proceed | revise | escalate
Artifact-hash: <sha of the artifact this verdict judged>   # a later edit can't inherit the verdict
Uncertainties: <concrete unknowns, or "none">              # any entry ⇒ borderline (replaces confidence)
Rationale: <1–2 sentences>
Required changes: <bullets, each tagged `rooted in: requirements|architecture|prompts`, or "none">  # iff revise
Escalation: <one-line reason, or "none">                   # iff escalate
Ledger: delegate-decisions.md#<id>.<n>
```

- `proceed` — Conductor continues.
- `revise` — Conductor runs a revision loop against "Required changes", routing each by its
  `rooted in:` owner (so the fix goes to the right specialist — a real relay failure was an addendum
  left on the wrong owner). The delegate then re-reviews as a **new attempt** (`<id> attempt n+1`,
  new verdict). A **revision cap** applies: hitting it escalates (the relay's exhausted-limit rule).
- `escalate` — the run pauses; the watcher surfaces the reason to Robin (below).
- `Uncertainties` replaces a self-reported confidence score — confidence is poorly calibrated and,
  worse, never catches a *confidently wrong* `proceed`. Any non-empty entry auto-flags **borderline**.
  This does not by itself solve the self-audit gap — see "Reality check".
- **The model emits these fields as structured output; the shell bridge writes the file** — the
  delegate has no repo/log/state write access (least privilege).

`agents/orchestrator.md` gets a short "consuming a delegate verdict" block: parse the structured
fields, verify `Artifact-hash` still matches, act by Decision, and **never proceed on a malformed or
hash-mismatched verdict — treat it as `escalate`.**

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
- **Conductor dies mid-wait.** The waiting party can die too. The watcher monitors Conductor
  liveness by **process/PID + Monitor-task state + request age** — *not* a `state.json` heartbeat (a
  blocked-by-design Conductor has a stale timestamp, and a second concurrent JSON writer is a hazard).
  A wait past a per-checkpoint-type timeout (high-stakes get longer) escalates rather than hangs.
- **Atomic requests + worker locking, not just verdicts.** Requests are written atomically too; on a
  watcher restart two delegates must not both claim one request — a deterministic claim/lock +
  idempotency key prevents double ledger appends.
- **No supervisor today.** Nothing launches the three parties, records the Conductor session ID/PID,
  restarts `Monitor` after a resume (it is not restored automatically), or tears down at run close.
  That launcher/supervisor is part of the build, not an afterthought.

Because the shell bridge (not the model) owns all writes, atomicity, locking, and idempotency live in
one place. It's standard "file as a queue" hygiene — worth a real `bridge` helper, not a one-liner.

### Escalation channel

When the delegate writes `Decision: escalate`, the watcher pings Robin and the run **halts** — note
this framework's workflows are sequential, so there is no "everything else flowing" in parallel; an
escalation stops the run until answered (`execute-plan.md:141`). The escalation message is
**self-contained** — task,
checkpoint, artifact path, and the delegate's rationale — so Robin can decide from his phone
without opening the run dir. v1 default: pause + a local desktop notification. Recommended v2:
route through the existing rheo Telegram bot / M.O.T. rail so Robin can answer from his phone and
the run resumes — the concrete "only novel decisions bubble up" mechanism.

One guard, because it's a tempting mistake (and one reviewer suggested it): an escalation that goes
unanswered **holds and re-notifies — it never times out into a default action.** Auto-proceeding on
an escalation timeout would reintroduce exactly the silent-pass failure mode this whole design
exists to prevent. A *non-escalation* checkpoint wait can have a timeout; a genuine escalation
cannot.

### Slices

- **v1 (proves the token claim; Robin still pulls the trigger):** Conductor writes the request and
  blocks; the delegate is a headless `claude -p` Robin runs via a one-line script when a request
  appears. Proves the mailbox, the cheap file-based review, and resume-from-verdict with no
  transcript resume. Robin no longer *reasons* at checkpoints — he runs a command.
- **v2 (autonomous):** add the watcher (file-watch → auto-spawn) + the Telegram escalation rail.
  Robin is out except for escalations.

### Self-audit — the gate before the delegate runs unattended

The gate-theater problem (Reality check) has no clean answer from *inside* the delegate: a
confidently-wrong `proceed` won't list its own `Uncertainties`, so it never reaches Robin's
borderline review. v2 must not run unattended until an **external** check exists. The mechanism:

- A cold auditor — The Notary (05) or a second fresh Challenger spawn — re-reviews a **random
  sample** of `proceed` verdicts (1 in N) against the same artifacts the delegate saw, **blind to the
  delegate's verdict**.
- A mismatch (the auditor would have escalated or revised where the delegate proceeded) is logged,
  fed back as a calibration signal, and surfaced to Robin.
- The sample rate starts high and drops only while the measured mismatch rate stays near zero — the
  same earn-trust ramp the Principal uses.

The **bridge** (not the model) picks the sample and spawns the auditor, so this is not the delegate
grading itself — it satisfies the gate-theater rule (script-orchestrated + cold-reviewer-checkable).
Until this exists and reads clean, v2 stays attended. This is the concrete answer to the deepest
open problem, and the one piece a v1→v2 promotion should turn on.

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
- v2 does not run unattended until the self-audit gate exists and reads clean — a cold auditor
  samples `proceed` verdicts blind, and the measured mismatch rate is near zero (see "Self-audit")
- The critic tier is chosen by measurement (the Bundle 04 replay), not asserted (see "Model routing")
