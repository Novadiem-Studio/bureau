# write-article — reducing the pipeline signature (texture review)

**Author:** The Conductor (main session) · **Date:** 2026-06-25
**Status:** proposal / design review (not yet promoted to canon)
**Evidence base:** direct observation of 4 full `write-article` runs on 2026-06-25 — `deny-by-default-grounding`, `gate-the-flow-not-the-judgment`, `the-pipeline-that-wrote-this`, `growoperative-foaf-protocol-architecture`. Claims below cite those runs.

Goal: reduce the detectable "strong pipeline" signature while preserving the non-negotiables (cold proofreader, versioned spine + manifest, generous-but-guarded reconcile, house-voice baseline, two distinct humanizer passes, standing-authorization automation, source-only figure-grounding, fail-closed safety).

---

## 1. Diagnosis — where the signature actually comes from

The remaining tell is not AI slop (the pipeline removes that well). It is **convergence**: every article is pulled toward the same attractor by several forces that compound. From the 4 runs:

**(a) One calibration exemplar homogenizes everything.** Every run's Counselor (frame) AND Scribe (outline + draft) read the SAME file, `one-process-one-file.mdx`, as the voice/shape calibration. Four articles voice-matched to one exemplar will rhyme. This is the single largest cross-article force.

**(b) The arc is templated.** The workflow's step-3 outline ships a "suggested arc" and the frame reinforces it. All 4 articles landed the same skeleton: hook that names the default/wrong way → the mechanism → an honest "where it breaks" / limits section → an aphoristic closer that restates the thesis. Evidence: every run has a "Where it breaks" (or "What is actually live") section, and every closer is a thesis-echo — "The model can't leak what it was never given." / "the small set of decisions it is not allowed to make." / "You are reading the result of that." / "more honest for having been designed as though it might." Same rhetorical move, four times.

**(c) Both humanizer passes SUBTRACT; nothing ADDS texture.** Pass 1 strips AI tells/vocab; pass 2 smooths read-aloud rhythm. Both regress toward a clean mean. Neither is licensed to introduce idiosyncrasy. The net is a narrow band of "clean technical prose," and pass 2's own signature move — "break a monotone run with a short declarative" — recurs across all 4 runs, producing a repeated cadence: "They are Tuesday." / "Cheap. Recoverable." / "Expensive. Irreversible." / "No broker. No message queue. No shared memory. No parked session." Good lines individually; a fingerprint in aggregate.

**(d) Identical voice rules → identical lexical fingerprint.** Same banned-word list, same no-em-dash rule (so the same colon/period rhythm), same "name the price" instinct → the same limits-section beat every time.

**(e) Revise + reconcile optimize toward "tight."** Structural revise and generous reconcile both push toward the most-optimized phrasing. "Maximally tight" reads engineered. Reconcile adopts "as good or better," which sands off the rougher-but-more-human option on ties.

**(f) No variance is injected anywhere.** Same models, same instructions, same exemplar, no per-run knob. Micro-variation has nothing to come from.

**(g) The systemic risk — a self-imitation feedback loop.** As published articles accumulate and become the calibration corpus, the pipeline increasingly imitates its OWN past output, amplifying the signature over time. Today it's one exemplar; left alone it becomes a closed loop that sharpens the tell with every run.

**Summary:** the signature is manufactured at four points — the single exemplar (b/a), the subtractive-only humanizers (c), the optimize-to-tight revise/reconcile (e), and the templated arc/closer (b). Fixing those four, surgically, removes most of it.

---

## 2. Proposed changes (surgical)

### A. Diversify the calibration exemplar + break the self-imitation loop  — *root cause a, g*
- Replace the hardcoded single calibration (`one-process-one-file.mdx`) with a small curated SET in `config/calibration-exemplars/` (3-5 pieces). The Conductor passes a DIFFERENT one per run — selected by topic-fit, or rotated by run index (vary the prompt by index, since `Math.random` is unavailable in scripts).
- Include at least one or two **non-pipeline, human-written** exemplars (a piece Robin wrote by hand, or an outside writer he admires) so the calibration target is NOT the pipeline's own output. This is what breaks loop (g).
- Mechanism: a config list + the Conductor selecting and passing the exemplar path into the Counselor/Scribe spawns instead of hardcoding it.
- **Tradeoff:** auditability unaffected (logged input). Cost ~0. Safety unaffected. House voice PRESERVED — all exemplars are in-house; diversity is *within* the house. Risk: low (exemplars must be genuinely good). This is the highest-leverage, lowest-risk change.

### B. Re-scope humanizer pass 2 to ADD texture (+ a new humanizer `texture` lens)  — *root cause c*
- Change pass 2's objective from "read-aloud rhythm" to "**rhythm + human texture**": explicitly licensed to LEAVE or INTRODUCE mild unevenness — an occasional slightly-long sentence, a sentence that opens with "And"/"But", a brief aside, a less-optimized but more natural phrasing, varied paragraph lengths, a light first-person hedge where it fits. The pass must distinguish **real AI tells (remove)** from **human unevenness (keep/allow)**.
- This requires a NEW LENS in the `humanizer` skill (the one genuine new capability): a "human texture" section defining what good human roughness looks like — sentence-length outliers, sentence-initial conjunctions, a vivid-but-imperfect metaphor, mild emphatic redundancy, a personal aside — VERSUS what is still slop (vagueness, hedging stacks, banned words, chattiness, filler). Without this rubric, a texture pass just adds slop.
- Optional sibling **B2 (a light pass 3 "texture" just before format/proofreader)** for runs that want more: a deliberately subjective, additive-only pass that does nothing but introduce micro-variation. Gate it behind the config knob in C so it is not the default.
- **Tradeoff:** B1 is instruction + skill change, no new step, no extra cost, auditability unchanged (still a versioned stage). B2 adds a stage + version (more spine, more cost, but cleaner separation and a clearer audit of "what texture did"). **Safety:** the real risk is reintroducing slop / reducing precision. Mitigations: texture pass touches **cadence/phrasing only, never facts/numbers/code/figure-grounded claims** (hard guard); it runs AFTER the de-slop pass and BEFORE the cold proofreader (which still catches howlers); the banned-list still applies.

### C. Per-run `voice-texture` knob (controlled variance)  — *root cause f; cross-article variety*
- Add a per-run setting (in the per-run `article-passes.json`, or a small `RUN_DIR/voice.json`): `texture: standard | light | loose`.
  - `standard` (default) = today's two passes, unchanged.
  - `light` = pass 2 re-scoped per B1 (less aggressive polish).
  - `loose` = B1 + the optional B2 pass 3 + the Scribe "leave-it" guard (D) dialed up.
- The Conductor (or Robin) sets it per run, so SOME articles get looser polish → natural variation ACROSS the body of work without changing the default for every piece.
- **Tradeoff:** small, auditable config addition (log it in state/manifest). Cost: only `loose` adds a pass. Safety: unchanged (proofreader still gates). The variance is the intended effect.

### D. Scribe revise/reconcile — license "good enough, leave it"  — *root cause e*
- Add an explicit anti-over-optimization guard to the revise and reconcile instructions: "when a passage is already clear and in voice, prefer leaving it slightly unpolished to making it maximally tight; do not optimize phrasing that is not broken; a little unevenness is human." For reconcile: when two phrasings are equally clear, **ties go to the more natural / less-optimized** one, not the tightest.
- **Tradeoff:** instruction-only, no new step, no cost, auditability unchanged. Risk: "leave it rough" misread as "leave slop" — scope it to clear-and-in-voice passages only; the voice floor and de-slop pass still run. Near-free; pairs naturally with A and B.

### E. Structural / opening variance  — *root cause b*
- Replace the single "suggested arc" in the outline step with a **small menu** the Counselor/Scribe selects from BY FIT: principle→mechanism→tradeoff (current default), narrative/chronological, problem-first/investigation, comparison, question-driven. And explicitly permit NOT closing on an aphoristic thesis-restatement — sometimes end on a fact, a question, or just stop (the house rules already allow this; the pipeline ignores it).
- Vary openings too: not always "name the default, then the sharper truth" — sometimes open mid-scene, on a number, on a question.
- **Tradeoff:** instruction change to the outline + frame steps. Risk: forcing artificial diversity can hurt fit — so it is a MENU selected by topic fit, never a mandate to differ. Auditability/cost/safety unchanged. Higher effort and higher risk-of-misfire than A-D; stage it after the voice-texture changes land and can be measured.

---

## 3. New skills / lenses required

Only one genuinely new capability: a **`texture` lens for the `humanizer` skill** (Section 2B). It is the linchpin — it gives any texture pass (B1/B2) a rubric for "human roughness vs. slop," without which "add texture" degrades to "add slop." Everything else is instruction or config changes to existing roles. No new agent roles are needed.

---

## 4. Tradeoff matrix

| Change | Auditability | Cost | Safety | House-voice consistency | Effort | Leverage |
|---|---|---|---|---|---|---|
| A. Diverse + external exemplars | No change (logged input) | ~0 | No change | Preserved (variety within house) | Low | **High** |
| B1. Re-scope pass 2 + texture lens | No change (same stage) | ~0 | Guarded: cadence-only, runs before proofreader | Slightly looser by design | Low-Med | **High** |
| B2. Optional pass 3 | +1 version/stage (more spine) | +1 pass when on | Same guard as B1 | Looser when on | Med | Med |
| C. `voice-texture` knob | +1 logged config field | Only `loose` adds a pass | No change | Intentionally variable across corpus | Med | Med |
| D. Scribe "leave-it" guard | No change | ~0 | Low risk (scoped to clear/in-voice) | Slightly looser | Low | Med |
| E. Structural menu | No change | ~0 | No change | More varied shapes | Med-High | Med |

**The core tension to name honestly:** auditability/reproducibility and human texture pull against each other. These changes add *controlled* non-determinism (the explicit goal). The audit trail is fully preserved — every texture pass is still an immutable versioned stage — but the OUTPUT becomes intentionally less uniform and less reproducible run-to-run. That is the feature, not a regression; it just should be a conscious choice, logged per run.

---

## 5. Prioritized recommendation (implement first)

1. **A — diversify the calibration exemplar + add 1-2 external human exemplars.** Highest leverage, lowest risk, ~zero cost, no auditability/safety/house-voice impact. It attacks the #1 homogenizer AND the self-imitation loop. Do this first.
2. **B1 + the humanizer `texture` lens.** Turns the second humanizer pass from purely subtractive to additive-with-guardrails. Instruction + skill change, no new step, cheap, auditable. The `texture` lens is the key new capability and unlocks C/B2 later.
3. **D (Scribe "leave-it" guard) + C (the `voice-texture` knob).** D is near-free and stops the optimize-to-tight drift; C gives deliberate variation across the body of work and a clean home for `light`/`loose` modes.

Stage **E (structural variance)** and **B2 (optional pass 3)** after 1-3 land, so their effect can be measured against the baseline rather than guessed at.

---

## 6. Implementation note (process)

These changes touch canon/process surfaces (`workflows/write-article.md`, `agents/scribe.md`, `agents/voice.md`, the `humanizer` skill, `config/`). Implementing them is itself a canon change and should run through the framework's own change process: a `Promotion to canon: yes/no` declaration on the implementing run, a fresh `battle-test.md`, and a cold Challenger review — i.e. the pipeline should review its own modification the way it reviews everything else. Recommend implementing A first as a standalone, low-risk change, measuring the next few articles, then B1+lens.
