# Framework evaluation log

The running ledger of every evaluation pass against real bureau runs, what it found, and what
we changed in the framework in response. This is the **memory across sessions**: read it before
you evaluate the framework or edit a persona, so you start from what prior passes already
discovered instead of from zero.

It completes a three-doc system:
- `challenger-pattern-analysis.md` — the **method** (how to mine runs into patterns; the frozen taxonomy).
- `architect-challenger-patterns.md` — the **synthesis** (current state of the pattern taxonomy + the Architect pre-flight checklist).
- `framework-evaluation-log.md` (this file) — the **ledger** (what we evaluated, what held, what we changed, when).

**How to append.** Newest entry at the TOP. One entry per evaluation pass or framework-change
session. Keep each entry to the fixed shape below so passes stay comparable over time (the same
discipline `challenger-pattern-analysis.md` demands of the taxonomy). Record corrections as
`file — rule`, and always separate **what we changed** from **open levers we did not implement**.

**Why a doc and not just git history.** Git history *should* be the trend source, but bureau is
currently subject to an auto-committer that bundles unrelated changes under generated,
misleading messages (see entry 2026-06-24). Until that is fixed, this hand-written ledger is the
authoritative record of what changed and why.

Entry shape:
```
## <date> — <one-line title>
**Evaluated:** <run(s) / artifacts>
**Against:** <baseline — which doc/version>
**What held:** <taxonomy / behaviour that reproduced>
**What was new or wrong:** <new patterns, methodological findings>
**Corrections made:** <file — rule>  (committed? where)
**Open levers (NOT implemented):** <proposed changes that need a bigger decision>
```

---

## 2026-06-24 — First dated eval: run 20260623-push-notifications-review vs the patterns doc

**Evaluated:** `growoperative-app/.bureau/runs/20260623-push-notifications-review` — a feature run
(idea-review → spec → plan → prompts → backend build → client build) with **5 Challenger passes**
(idea-review, round-1 spec/plan, round-2 prompts, backend build-diff, client build-diff). On its
own it is more than half the pass-count of the original 8-run synthesis, so it is a strong
out-of-sample test.

**Against:** `architect-challenger-patterns.md` as it stood after the original 8-run synthesis
(2026-06-14 → 2026-06-22).

**What held:**
- The taxonomy generalizes. Nearly every pattern recurred and the top-of-table ordering
  reproduced: `missing-edge-case` dominated again, with `internal-contradiction`,
  `under-specified`, `wrong-api-shape`, and `external-dependency-unstated` close behind.
  `false-positive-risk` recurred cleanly (a reviewer ran `git diff master` against the wrong
  base, flagged scope-bleed, self-corrected). Only `caller-cant-supply` (n=1 originally) was absent.
- The multi-pass cold-spawn design genuinely forces re-discovery, it is not rubber-stamping.
  Round-2 was spawned cold and NOT shown round-1 / B1 / B2; it independently re-derived that the
  B1 fix was correct and found 7 net-new prompt-level issues. The client build pass found the
  warm-tap deep-link drain bug that no earlier pass caught.

**What was new or wrong:**
- **New pattern: `false-reuse`.** The highest-severity finding at BOTH the idea and spec stage
  was the same shape — the plan claimed routing was "already built" / "no new logic needed" when
  it was net-new. Two Blockers. The inverse of `reuse-missed` and more expensive. Root cause is
  authoring-side: the claim named no symbol, so the symbol-triggered self-checks could not see it.
- **The encoded checklist did not pre-empt.** The pre-flight checklist is already encoded into
  the Architect's pre-handoff self-check (`agents/architect.md`), yet it did not stop the round-1
  Blockers. Two reasons, both now recorded as lessons: (a) a self-check that triggers on *named
  symbols* is blind to a hand-wave that names none; (b) a check nobody is forced to *evidence*
  does not reliably fire.
- **"0 Blockers" from round-2 on is partly an artifact.** Real part: cold re-derivation + new
  findings (above). Artifact part: later passes review a target already hardened against the
  known failures, and one genuine go-live bug (warm-tap drain — the review itself says it "will
  not work when push goes live") was filed as a **Warning**, not a Blocker, which flatters the count.

**Corrections made** (committed in `0975623`, working tree clean):
- `agents/architect.md` — new self-check **row 11, Reuse-claim audit**: in existing-project mode,
  any "already built / reuse / no new logic" claim must name a `symbol@path` at the call level it
  must exist at; a reuse claim that names no symbol is itself the defect. This is the rule that
  makes a hand-wave catchable by the existing symbol-triggered checks.
- `agents/critic.md` — **bidirectional evidence rule** in Existing-project mode: any
  exists / does-not-exist claim carries `symbol + path + grep`, both when refuting a reuse claim
  and when declaring something net-new (the absence-grep is the guard against inducing duplicate code).
- `docs/evaluation/architect-challenger-patterns.md` — added the `false-reuse` pattern (frequency table with
  a provenance dagger, full description, checklist item 13) and a `§ Validation — run 20260623`
  section. Taxonomy was *extended by appending*, not renamed — compliant with the freeze rule in
  `challenger-pattern-analysis.md`.

**Open levers (NOT implemented — each needs a real schema/adjudication change, not persona prose):**
- Make the Architect **state which self-checks it ran, with evidence**, before the Challenger
  spawns. Right now the self-check's existence changed nothing about the round-1 Blocker count.
- Tighten **Warning-vs-Blocker severity** so a finding that means "will not work when the feature
  goes live" cannot be filed as a Warning.
- Fix the **auto-committer**: it committed this session's edits under a generated, voice-violating
  message with no `Co-Authored-By`, and bundled an unrelated `ideas/agent-framework/index.md`
  change into the same commit. This directly undermines using git history as the trend source.

---

## Genesis — the original 8-run synthesis (pre-ledger)

Before this ledger existed, the only record of evaluation work was the synthesis output itself.
Treat `architect-challenger-patterns.md` (the Pattern Frequency Table + Full Findings Table,
2026-06-14 → 2026-06-22, 9 Challenger passes across 8 runs: cryptowatch, invite-qr, stakeholder,
rheo-memory-track1, upwork-desk, gmail-llm, memory-track2, nav-runtime) as entry zero. The method
that produced it is in `challenger-pattern-analysis.md`.
